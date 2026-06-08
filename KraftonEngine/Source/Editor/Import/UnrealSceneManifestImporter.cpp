#include "Editor/Import/UnrealSceneManifestImporter.h"

#include "Component/Primitive/InstancedStaticMeshComponent.h"
#include "Component/Primitive/DecalComponent.h"
#include "Component/Primitive/StaticMeshComponent.h"
#include "Component/Primitive/HeightFogComponent.h"
#include "Component/Light/AmbientLightComponent.h"
#include "Component/Light/DirectionalLightComponent.h"
#include "Component/Light/PointLightComponent.h"
#include "Component/Light/SpotLightComponent.h"
#include "Core/Logging/Log.h"
#include "Core/Types/CollisionTypes.h"
#include "Engine/Platform/Paths.h"
#include "GameFramework/Actor/StaticMeshActor.h"
#include "GameFramework/Actor/DecalActor.h"
#include "GameFramework/AActor.h"
#include "GameFramework/Actor/HeightFogActor.h"
#include "GameFramework/Light/AmbientLightActor.h"
#include "GameFramework/Light/DirectionalLightActor.h"
#include "GameFramework/Light/PointLightActor.h"
#include "GameFramework/Light/SpotLightActor.h"
#include "GameFramework/World.h"
#include "Materials/Graph/MaterialGraphAsset.h"
#include "Materials/Material.h"
#include "Materials/MaterialManager.h"
#include "Math/Rotator.h"
#include "Math/Transform.h"
#include "Mesh/MeshManager.h"
#include "Mesh/Importer/MeshImportOptions.h"
#include "Mesh/Static/StaticMesh.h"
#include "Object/FName.h"
#include "SimpleJSON/json.hpp"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <initializer_list>
#include <sstream>

namespace
{
	struct FTextureSamplePins
	{
		uint32 RGB = 0;
		uint32 R = 0;
		uint32 G = 0;
		uint32 B = 0;
		uint32 A = 0;
	};

	struct FScenePlacementImportRecord
	{
		json::JSON* ActorObject = nullptr;
		UStaticMesh* Mesh = nullptr;
		FString MeshKey;
		FVector Location;
		FVector RotationEuler;
		FVector Scale = FVector(1.0f, 1.0f, 1.0f);
		FMatrix WorldMatrix = FMatrix::Identity;
		FString CollisionString;
		ECollisionEnabled Collision = ECollisionEnabled::NoCollision;
		bool bVisible = true;
		bool bCastShadow = true;
		bool bNegativeScale = false;
		bool bHasWorldMatrix = false;
		FString GroupKey;
	};

	void ApplyActorMaterials(
		json::JSON& ActorObject,
		UStaticMeshComponent* Component,
		const TMap<FString, UMaterial*>& ImportedMaterials,
		FUnrealSceneImportResult& Result);

	bool ReadFile(const std::filesystem::path& Path, FString& OutContent)
	{
		std::ifstream File(Path, std::ios::binary);
		if (!File.is_open())
		{
			return false;
		}

		std::ostringstream Buffer;
		Buffer << File.rdbuf();
		OutContent = Buffer.str();
		return true;
	}

	bool ReadNumber(const json::JSON& Value, float& OutValue)
	{
		if (Value.JSONType() == json::JSON::Class::Floating)
		{
			OutValue = static_cast<float>(Value.ToFloat());
			return true;
		}
		if (Value.JSONType() == json::JSON::Class::Integral)
		{
			OutValue = static_cast<float>(Value.ToInt());
			return true;
		}
		return false;
	}

	bool ReadVector3(json::JSON& Object, const char* Key, FVector& OutValue)
	{
		if (!Object.hasKey(Key))
		{
			return false;
		}

		json::JSON& Array = Object[Key];
		if (Array.JSONType() != json::JSON::Class::Array || Array.length() < 3)
		{
			return false;
		}

		float X = 0.0f;
		float Y = 0.0f;
		float Z = 0.0f;
		if (!ReadNumber(Array.at(0), X) || !ReadNumber(Array.at(1), Y) || !ReadNumber(Array.at(2), Z))
		{
			return false;
		}

		OutValue = FVector(X, Y, Z);
		return true;
	}

	bool ReadVector4(json::JSON& Object, const char* Key, FVector4& OutValue)
	{
		if (!Object.hasKey(Key))
		{
			return false;
		}

		json::JSON& Array = Object[Key];
		if (Array.JSONType() != json::JSON::Class::Array || Array.length() < 3)
		{
			return false;
		}

		float X = 1.0f;
		float Y = 1.0f;
		float Z = 1.0f;
		float W = 1.0f;
		if (!ReadNumber(Array.at(0), X) ||
			!ReadNumber(Array.at(1), Y) ||
			!ReadNumber(Array.at(2), Z))
		{
			return false;
		}
		if (Array.length() >= 4)
		{
			ReadNumber(Array.at(3), W);
		}

		OutValue = FVector4(X, Y, Z, W);
		return true;
	}

	bool ReadMatrix4x4(json::JSON& Object, const char* Key, FMatrix& OutValue)
	{
		if (!Object.hasKey(Key))
		{
			return false;
		}

		json::JSON& MatrixValue = Object[Key];
		if (MatrixValue.JSONType() != json::JSON::Class::Array)
		{
			return false;
		}

		FMatrix Matrix = FMatrix::Identity;
		if (MatrixValue.length() == 16)
		{
			for (int32 Row = 0; Row < 4; ++Row)
			{
				for (int32 Column = 0; Column < 4; ++Column)
				{
					float Value = 0.0f;
					if (!ReadNumber(MatrixValue.at(Row * 4 + Column), Value))
					{
						return false;
					}
					Matrix.M[Row][Column] = Value;
				}
			}
			OutValue = Matrix;
			return true;
		}

		if (MatrixValue.length() < 4)
		{
			return false;
		}

		for (int32 Row = 0; Row < 4; ++Row)
		{
			json::JSON& RowValue = MatrixValue.at(Row);
			if (RowValue.JSONType() != json::JSON::Class::Array ||
				RowValue.length() < 4)
			{
				return false;
			}

			for (int32 Column = 0; Column < 4; ++Column)
			{
				float Value = 0.0f;
				if (!ReadNumber(RowValue.at(Column), Value))
				{
					return false;
				}
				Matrix.M[Row][Column] = Value;
			}
		}

		OutValue = Matrix;
		return true;
	}

	FString ReadString(json::JSON& Object, const char* Key, const FString& DefaultValue = FString())
	{
		if (!Object.hasKey(Key))
		{
			return DefaultValue;
		}

		bool bOk = false;
		const FString Value = Object[Key].ToString(bOk);
		return bOk ? Value : DefaultValue;
	}

	FString ToLowerAscii(FString Value)
	{
		std::transform(Value.begin(), Value.end(), Value.begin(),
			[](unsigned char Character)
			{
				return static_cast<char>(std::tolower(Character));
			});
		return Value;
	}

	bool ContainsAny(const FString& Value, std::initializer_list<const char*> Terms)
	{
		for (const char* Term : Terms)
		{
			if (Value.find(Term) != FString::npos)
			{
				return true;
			}
		}
		return false;
	}

	bool IsDecalIdentity(const FString& Identity)
	{
		return ContainsAny(Identity, { "decal" });
	}

	bool ReadNamedScalar(
		json::JSON& Object,
		std::initializer_list<const char*> Names,
		float& OutValue)
	{
		if (Object.JSONType() != json::JSON::Class::Object)
		{
			return false;
		}

		for (auto& Pair : Object.ObjectRange())
		{
			const FString Key = ToLowerAscii(Pair.first);
			for (const char* Name : Names)
			{
				if (Key == Name && ReadNumber(Pair.second, OutValue))
				{
					return true;
				}
			}
		}
		return false;
	}

	bool ReadNamedVector(
		json::JSON& Object,
		std::initializer_list<const char*> Names,
		FVector4& OutValue)
	{
		if (Object.JSONType() != json::JSON::Class::Object)
		{
			return false;
		}

		for (auto& Pair : Object.ObjectRange())
		{
			const FString Key = ToLowerAscii(Pair.first);
			bool bNameMatches = false;
			for (const char* Name : Names)
			{
				if (Key == Name)
				{
					bNameMatches = true;
					break;
				}
			}
			if (!bNameMatches ||
				Pair.second.JSONType() != json::JSON::Class::Array ||
				Pair.second.length() < 3)
			{
				continue;
			}

			float X = 1.0f;
			float Y = 1.0f;
			float Z = 1.0f;
			float W = 1.0f;
			if (!ReadNumber(Pair.second.at(0), X) ||
				!ReadNumber(Pair.second.at(1), Y) ||
				!ReadNumber(Pair.second.at(2), Z))
			{
				continue;
			}
			if (Pair.second.length() >= 4)
			{
				ReadNumber(Pair.second.at(3), W);
			}

			OutValue = FVector4(X, Y, Z, W);
			return true;
		}
		return false;
	}

	bool ReadBool(json::JSON& Object, const char* Key, bool DefaultValue)
	{
		if (!Object.hasKey(Key))
		{
			return DefaultValue;
		}

		bool bOk = false;
		const bool Value = Object[Key].ToBool(bOk);
		return bOk ? Value : DefaultValue;
	}

	float ReadFloat(json::JSON& Object, const char* Key, float DefaultValue)
	{
		if (!Object.hasKey(Key))
		{
			return DefaultValue;
		}

		float Value = DefaultValue;
		return ReadNumber(Object[Key], Value) ? Value : DefaultValue;
	}

	FString SanitizePathSegment(FString Value)
	{
		for (char& Character : Value)
		{
			const unsigned char Byte = static_cast<unsigned char>(Character);
			if (!std::isalnum(Byte) && Character != '_' && Character != '-')
			{
				Character = '_';
			}
		}

		return Value.empty() ? FString("UnrealScene") : Value;
	}

	FString BuildActorName(json::JSON& ActorObject)
	{
		FString Name = ReadString(ActorObject, "name", "StaticMeshActor");
		const FString Id = ReadString(ActorObject, "id");
		if (!Id.empty())
		{
			Name += "_";
			Name += Id.substr(0, std::min<size_t>(8, Id.size()));
		}
		return Name;
	}

	FString BuildMaterialSignature(json::JSON& ActorObject)
	{
		if (!ActorObject.hasKey("materials") ||
			ActorObject["materials"].JSONType() != json::JSON::Class::Array)
		{
			return FString();
		}

		FString Signature;
		for (json::JSON& MaterialValue : ActorObject["materials"].ArrayRange())
		{
			bool bOk = false;
			const FString SourceAsset = MaterialValue.ToString(bOk);
			if (!bOk)
			{
				continue;
			}

			Signature += std::to_string(SourceAsset.size());
			Signature += ":";
			Signature += SourceAsset;
			Signature += ";";
		}
		return Signature;
	}

	ECollisionEnabled ParseCollisionMode(const FString& Value)
	{
		if (Value.find("NO_COLLISION") != FString::npos)
		{
			return ECollisionEnabled::NoCollision;
		}
		if (Value.find("QUERY_AND_PHYSICS") != FString::npos)
		{
			return ECollisionEnabled::QueryAndPhysics;
		}
		if (Value.find("PHYSICS_ONLY") != FString::npos)
		{
			return ECollisionEnabled::PhysicsOnly;
		}
		if (Value.find("QUERY_ONLY") != FString::npos)
		{
			return ECollisionEnabled::QueryOnly;
		}
		return ECollisionEnabled::NoCollision;
	}

	FString BuildInstancingGroupKey(
		const FScenePlacementImportRecord& Record,
		const FString& MaterialSignature)
	{
		std::ostringstream Stream;
		Stream
			<< Record.MeshKey
			<< "|mat=" << MaterialSignature
			<< "|vis=" << (Record.bVisible ? 1 : 0)
			<< "|shadow=" << (Record.bCastShadow ? 1 : 0)
			<< "|collision=" << Record.CollisionString;
		return Stream.str();
	}

	FMatrix BuildPlacementMatrix(const FScenePlacementImportRecord& Record)
	{
		if (Record.bHasWorldMatrix)
		{
			return Record.WorldMatrix;
		}

		return FTransform(
			Record.Location,
			FRotator(Record.RotationEuler.Y, Record.RotationEuler.Z, Record.RotationEuler.X),
			Record.Scale).ToMatrix();
	}

	float GetScaleSign(float Value)
	{
		return Value < 0.0f ? -1.0f : 1.0f;
	}

	float GetBasisDeterminant(const FVector& X, const FVector& Y, const FVector& Z)
	{
		return X.Dot(Y.Cross(Z));
	}

	void DecomposePlacementMatrix(
		const FScenePlacementImportRecord& Record,
		FVector& OutLocation,
		FQuat& OutRotation,
		FVector& OutScale)
	{
		OutLocation = Record.Location;
		OutRotation = FRotator(
			Record.RotationEuler.Y,
			Record.RotationEuler.Z,
			Record.RotationEuler.X).ToQuaternion();
		OutScale = Record.Scale;

		if (!Record.bHasWorldMatrix)
		{
			return;
		}

		const FMatrix& Matrix = Record.WorldMatrix;
		const FVector BasisX(Matrix.M[0][0], Matrix.M[0][1], Matrix.M[0][2]);
		const FVector BasisY(Matrix.M[1][0], Matrix.M[1][1], Matrix.M[1][2]);
		const FVector BasisZ(Matrix.M[2][0], Matrix.M[2][1], Matrix.M[2][2]);

		float ScaleX = BasisX.Length();
		float ScaleY = BasisY.Length();
		float ScaleZ = BasisZ.Length();
		if (ScaleX <= 1.0e-6f || ScaleY <= 1.0e-6f || ScaleZ <= 1.0e-6f)
		{
			return;
		}

		float SignX = GetScaleSign(Record.Scale.X);
		float SignY = GetScaleSign(Record.Scale.Y);
		float SignZ = GetScaleSign(Record.Scale.Z);
		const float Determinant = GetBasisDeterminant(BasisX, BasisY, BasisZ);
		if (Determinant < 0.0f && SignX * SignY * SignZ > 0.0f)
		{
			SignX = -SignX;
		}
		else if (Determinant >= 0.0f && SignX * SignY * SignZ < 0.0f)
		{
			SignX = -SignX;
		}

		OutScale = FVector(ScaleX * SignX, ScaleY * SignY, ScaleZ * SignZ);

		FMatrix RotationMatrix = FMatrix::Identity;
		RotationMatrix.M[0][0] = BasisX.X / OutScale.X;
		RotationMatrix.M[0][1] = BasisX.Y / OutScale.X;
		RotationMatrix.M[0][2] = BasisX.Z / OutScale.X;
		RotationMatrix.M[1][0] = BasisY.X / OutScale.Y;
		RotationMatrix.M[1][1] = BasisY.Y / OutScale.Y;
		RotationMatrix.M[1][2] = BasisY.Z / OutScale.Y;
		RotationMatrix.M[2][0] = BasisZ.X / OutScale.Z;
		RotationMatrix.M[2][1] = BasisZ.Y / OutScale.Z;
		RotationMatrix.M[2][2] = BasisZ.Z / OutScale.Z;

		OutLocation = FVector(Matrix.M[3][0], Matrix.M[3][1], Matrix.M[3][2]);
		OutRotation = RotationMatrix.ToQuat().GetNormalized();
	}

	void ApplyPlacementTransform(AActor* Actor, const FScenePlacementImportRecord& Record)
	{
		if (!Actor)
		{
			return;
		}

		USceneComponent* Root = Actor->GetRootComponent();
		if (!Root)
		{
			return;
		}

		if (!Record.bHasWorldMatrix)
		{
			Actor->SetActorLocation(Record.Location);
			Actor->SetActorRotation(
				FRotator(Record.RotationEuler.Y, Record.RotationEuler.Z, Record.RotationEuler.X));
			Actor->SetActorScale(Record.Scale);
			return;
		}

		FVector Location;
		FQuat Rotation;
		FVector Scale;
		DecomposePlacementMatrix(Record, Location, Rotation, Scale);

		Root->SetRelativeLocation(Location);
		Root->SetRelativeRotationWithEulerHint(
			Rotation,
			Rotation.ToRotator());
		Root->SetRelativeScale(Scale);
	}

	void ApplyCommonStaticMeshComponentState(
		json::JSON& ActorObject,
		UStaticMeshComponent* Component,
		const FScenePlacementImportRecord& Record,
		const TMap<FString, UMaterial*>& ImportedMaterials,
		FUnrealSceneImportResult& Result)
	{
		Component->SetStaticMesh(Record.Mesh);
		Component->SetVisibility(Record.bVisible);
		Component->SetCastShadow(Record.bCastShadow);
		Component->SetCollisionEnabled(Record.Collision);
		ApplyActorMaterials(ActorObject, Component, ImportedMaterials, Result);
	}

	bool SpawnStaticMeshPlacement(
		UWorld* World,
		const FScenePlacementImportRecord& Record,
		const TMap<FString, UMaterial*>& ImportedMaterials,
		FUnrealSceneImportResult& Result)
	{
		AStaticMeshActor* Actor = World->SpawnActor<AStaticMeshActor>();
		if (!Actor)
		{
			++Result.SkippedActorCount;
			return false;
		}

		UStaticMeshComponent* Component = Actor->AddComponent<UStaticMeshComponent>();
		if (!Component)
		{
			World->DestroyActor(Actor);
			++Result.SkippedActorCount;
			return false;
		}

		Actor->SetRootComponent(Component);
		Actor->SetFName(FName(BuildActorName(*Record.ActorObject)));
		ApplyPlacementTransform(Actor, Record);
		Actor->SetVisible(Record.bVisible);
		ApplyCommonStaticMeshComponentState(
			*Record.ActorObject,
			Component,
			Record,
			ImportedMaterials,
			Result);

		++Result.ActorCount;
		++Result.EngineActorCount;
		return true;
	}

	bool SpawnInstancedStaticMeshGroup(
		UWorld* World,
		const TArray<FScenePlacementImportRecord>& PlacementRecords,
		const TArray<int32>& Indices,
		int32 GroupIndex,
		const TMap<FString, UMaterial*>& ImportedMaterials,
		FUnrealSceneImportResult& Result)
	{
		if (Indices.empty())
		{
			return false;
		}

		const FScenePlacementImportRecord& First = PlacementRecords[Indices.front()];
		AActor* Actor = World->SpawnActor<AActor>();
		if (!Actor)
		{
			return false;
		}

		UInstancedStaticMeshComponent* Component =
			Actor->AddComponent<UInstancedStaticMeshComponent>();
		if (!Component)
		{
			World->DestroyActor(Actor);
			return false;
		}

		TArray<FMatrix> InstanceTransforms;
		InstanceTransforms.reserve(Indices.size());
		for (int32 Index : Indices)
		{
			InstanceTransforms.push_back(BuildPlacementMatrix(PlacementRecords[Index]));
		}

		Actor->SetRootComponent(Component);
		Actor->SetFName(FName(
			FString("ISM_") + SanitizePathSegment(First.MeshKey) + "_" +
			std::to_string(GroupIndex)));
		Actor->SetActorLocation(FVector(0.0f, 0.0f, 0.0f));
		Actor->SetActorRotation(FRotator(0.0f, 0.0f, 0.0f));
		Actor->SetActorScale(FVector(1.0f, 1.0f, 1.0f));
		Actor->SetVisible(First.bVisible);
		ApplyCommonStaticMeshComponentState(
			*First.ActorObject,
			Component,
			First,
			ImportedMaterials,
			Result);
		Component->SetInstanceTransforms(InstanceTransforms);

		const int32 InstanceCount = static_cast<int32>(InstanceTransforms.size());
		Result.ActorCount += InstanceCount;
		++Result.EngineActorCount;
		++Result.InstancedGroupCount;
		Result.InstancedPlacementCount += InstanceCount;
		return true;
	}

	bool CopyFileIfNeeded(const std::filesystem::path& Source, const std::filesystem::path& Destination)
	{
		std::error_code Error;
		if (std::filesystem::exists(Source, Error))
		{
			Error.clear();
			if (std::filesystem::exists(Destination, Error))
			{
				Error.clear();
				if (std::filesystem::equivalent(Source, Destination, Error) && !Error)
				{
					return true;
				}
				Error.clear();
				const auto SourceSize = std::filesystem::file_size(Source, Error);
				if (!Error)
				{
					Error.clear();
					const auto DestinationSize = std::filesystem::file_size(Destination, Error);
					if (!Error && SourceSize == DestinationSize)
					{
						Error.clear();
						const auto SourceTime = std::filesystem::last_write_time(Source, Error);
						if (!Error)
						{
							Error.clear();
							const auto DestinationTime = std::filesystem::last_write_time(Destination, Error);
							if (!Error && SourceTime == DestinationTime)
							{
								return true;
							}
						}
					}
				}
			}
			Error.clear();
		}

		std::filesystem::create_directories(Destination.parent_path(), Error);
		if (Error)
		{
			return false;
		}

		Error.clear();
		std::filesystem::copy_file(
			Source,
			Destination,
			std::filesystem::copy_options::overwrite_existing,
			Error);
		return !Error;
	}

	bool IsSafeRelativePath(const std::filesystem::path& Path)
	{
		return !Path.is_absolute() &&
			std::find(Path.begin(), Path.end(), std::filesystem::path(L"..")) == Path.end();
	}

	uint32 FindPinId(
		const FMaterialGraphNode* Node,
		const char* DisplayName,
		EMaterialGraphPinKind Kind)
	{
		if (!Node)
		{
			return 0;
		}

		for (const FMaterialGraphPin& Pin : Node->Pins)
		{
			if (Pin.Kind == Kind && Pin.DisplayName.ToString() == DisplayName)
			{
				return Pin.PinId;
			}
		}
		return 0;
	}

	void AddGraphLink(FMaterialGraph& Graph, uint32 FromPin, uint32 ToPin)
	{
		if (FromPin != 0 && ToPin != 0)
		{
			Graph.AddLink(FromPin, ToPin);
		}
	}

	uint32 AddConstant(
		FMaterialGraph& Graph,
		float Value,
		float X,
		float Y)
	{
		FMaterialGraphNode* Node =
			Graph.AddNodeOfType(EMaterialGraphNodeType::ConstantFloat, X, Y, EMaterialDomain::Surface);
		Node->Value = FVector4(Value, 0.0f, 0.0f, 0.0f);
		return FindPinId(Node, "Value", EMaterialGraphPinKind::Output);
	}

	uint32 AddConstant3(
		FMaterialGraph& Graph,
		const FVector4& Value,
		float X,
		float Y)
	{
		FMaterialGraphNode* Node =
			Graph.AddNodeOfType(EMaterialGraphNodeType::ConstantFloat3, X, Y, EMaterialDomain::Surface);
		Node->Value = FVector4(Value.X, Value.Y, Value.Z, 1.0f);
		return FindPinId(Node, "Value", EMaterialGraphPinKind::Output);
	}

	uint32 AddMultiply(
		FMaterialGraph& Graph,
		uint32 A,
		uint32 B,
		float X,
		float Y)
	{
		FMaterialGraphNode* Node =
			Graph.AddNodeOfType(EMaterialGraphNodeType::Multiply, X, Y, EMaterialDomain::Surface);
		AddGraphLink(Graph, A, FindPinId(Node, "A", EMaterialGraphPinKind::Input));
		AddGraphLink(Graph, B, FindPinId(Node, "B", EMaterialGraphPinKind::Input));
		return FindPinId(Node, "Result", EMaterialGraphPinKind::Output);
	}

	FTextureSamplePins AddTextureSample(
		FMaterialGraph& Graph,
		const FString& TexturePath,
		EMaterialTextureSlot Slot,
		const FString& ParameterName,
		float X,
		float Y)
	{
		FMaterialGraphNode* Texture =
			Graph.AddNodeOfType(EMaterialGraphNodeType::TextureObject, X, Y, EMaterialDomain::Surface);
		Texture->TexturePath = TexturePath;
		Texture->TextureSlot = Slot;
		Texture->ParameterName = ParameterName;
		const uint32 TextureOutput =
			FindPinId(Texture, "Texture", EMaterialGraphPinKind::Output);

		FMaterialGraphNode* Sample =
			Graph.AddNodeOfType(EMaterialGraphNodeType::TextureSample, X + 220.0f, Y, EMaterialDomain::Surface);
		AddGraphLink(
			Graph,
			TextureOutput,
			FindPinId(Sample, "Texture", EMaterialGraphPinKind::Input));

		FTextureSamplePins Pins;
		Pins.RGB = FindPinId(Sample, "RGB", EMaterialGraphPinKind::Output);
		Pins.R = FindPinId(Sample, "R", EMaterialGraphPinKind::Output);
		Pins.G = FindPinId(Sample, "G", EMaterialGraphPinKind::Output);
		Pins.B = FindPinId(Sample, "B", EMaterialGraphPinKind::Output);
		Pins.A = FindPinId(Sample, "A", EMaterialGraphPinKind::Output);
		return Pins;
	}

	FString MakeMaterialGuid(const FString& Source)
	{
		uint64 Hash = 0xcbf29ce484222325ULL;
		for (unsigned char Character : Source)
		{
			Hash ^= static_cast<uint64>(Character);
			Hash *= 0x100000001b3ULL;
		}

		char Buffer[24] = {};
		std::snprintf(Buffer, sizeof(Buffer), "%016llX", static_cast<unsigned long long>(Hash));
		return Buffer;
	}

	bool IsNearlyWhite(const FVector4& Color)
	{
		return std::abs(Color.X - 1.0f) < 0.0001f &&
			std::abs(Color.Y - 1.0f) < 0.0001f &&
			std::abs(Color.Z - 1.0f) < 0.0001f;
	}

	bool ReadVectorValue(json::JSON& Value, FVector4& OutValue)
	{
		if (Value.JSONType() != json::JSON::Class::Array || Value.length() < 3)
		{
			return false;
		}

		float X = 1.0f;
		float Y = 1.0f;
		float Z = 1.0f;
		float W = 1.0f;
		if (!ReadNumber(Value.at(0), X) ||
			!ReadNumber(Value.at(1), Y) ||
			!ReadNumber(Value.at(2), Z))
		{
			return false;
		}
		if (Value.length() >= 4)
		{
			ReadNumber(Value.at(3), W);
		}

		OutValue = FVector4(X, Y, Z, W);
		return true;
	}

	bool IsBaseColorVectorName(const FString& Name)
	{
		const FString LowerName = ToLowerAscii(Name);
		return LowerName == "color multiply" ||
			LowerName == "base color" ||
			LowerName == "basecolor" ||
			LowerName == "color" ||
			LowerName == "tint" ||
			LowerName == "glass color";
	}

	bool HasNonEmptyArrayMember(json::JSON& Object, const char* Key)
	{
		return Object.hasKey(Key) &&
			Object[Key].JSONType() == json::JSON::Class::Array &&
			Object[Key].length() > 0;
	}

	void CopyObjectDefaults(json::JSON& Child, json::JSON& Parent, const char* Key)
	{
		if (!Parent.hasKey(Key) ||
			Parent[Key].JSONType() != json::JSON::Class::Object)
		{
			return;
		}

		if (!Child.hasKey(Key) ||
			Child[Key].JSONType() != json::JSON::Class::Object)
		{
			Child[Key] = json::JSON::Make(json::JSON::Class::Object);
		}

		for (auto& Pair : Parent[Key].ObjectRange())
		{
			if (!Child[Key].hasKey(Pair.first))
			{
				Child[Key][Pair.first] = Pair.second;
			}
		}
	}

	void ApplyTreeTrunkParentColorFallback(json::JSON& Child, json::JSON& Parent)
	{
		const FString MaterialIdentity = ToLowerAscii(
			ReadString(Child, "key") + " " +
			ReadString(Child, "baseMaterial") + " " +
			ReadString(Child, "sourceAsset"));
		if (!ContainsAny(MaterialIdentity, { "treetrunk", "tree_trunk", "tile_treetrunk" }) ||
			HasNonEmptyArrayMember(Child, "textures") ||
			!Child.hasKey("vectors") ||
			!Parent.hasKey("vectors") ||
			Child["vectors"].JSONType() != json::JSON::Class::Object ||
			Parent["vectors"].JSONType() != json::JSON::Class::Object)
		{
			return;
		}

		for (auto& ParentPair : Parent["vectors"].ObjectRange())
		{
			if (!IsBaseColorVectorName(ParentPair.first) ||
				!Child["vectors"].hasKey(ParentPair.first))
			{
				continue;
			}

			FVector4 ChildColor;
			FVector4 ParentColor;
			if (ReadVectorValue(Child["vectors"][ParentPair.first], ChildColor) &&
				ReadVectorValue(ParentPair.second, ParentColor) &&
				IsNearlyWhite(ChildColor) &&
				!IsNearlyWhite(ParentColor))
			{
				Child["vectors"][ParentPair.first] = ParentPair.second;
			}
		}
	}

	void ApplyMaterialParentFallback(json::JSON& Child, json::JSON& Parent)
	{
		if (!HasNonEmptyArrayMember(Child, "textures") &&
			HasNonEmptyArrayMember(Parent, "textures"))
		{
			Child["textures"] = Parent["textures"];
		}

		CopyObjectDefaults(Child, Parent, "scalars");
		CopyObjectDefaults(Child, Parent, "vectors");
		ApplyTreeTrunkParentColorFallback(Child, Parent);
	}

	json::JSON BuildEffectiveMaterialObject(
		json::JSON& MaterialObject,
		const TMap<FString, json::JSON*>& MaterialsBySourceAsset,
		int32 Depth = 0)
	{
		json::JSON Effective = MaterialObject;
		if (Depth >= 8)
		{
			return Effective;
		}

		const FString ParentSource = ReadString(MaterialObject, "baseMaterial");
		auto ParentIt = MaterialsBySourceAsset.find(ParentSource);
		if (ParentIt == MaterialsBySourceAsset.end() || !ParentIt->second)
		{
			return Effective;
		}

		json::JSON ParentEffective =
			BuildEffectiveMaterialObject(*ParentIt->second, MaterialsBySourceAsset, Depth + 1);
		ApplyMaterialParentFallback(Effective, ParentEffective);
		return Effective;
	}

	bool BuildMaterialGraph(
		json::JSON& MaterialObject,
		const TMap<FString, FString>& TexturePaths,
		FMaterialGraph& OutGraph,
		FString& OutRenderPass,
		FString& OutBlendState,
		FString& OutDepthState,
		FString& OutRasterState)
	{
		const FString BlendMode = ToLowerAscii(ReadString(MaterialObject, "blendMode"));
		const bool bMasked = ContainsAny(BlendMode, { "blend_masked", "masked" });
		const bool bTranslucent = ContainsAny(BlendMode, { "blend_translucent", "translucent" });

		OutRenderPass = bTranslucent ? "AlphaBlend" : "Opaque";
		OutBlendState = bTranslucent ? "AlphaBlend" : "Opaque";
		OutDepthState = bTranslucent ? "DepthReadOnly" : "Default";
		// UE scene manifests can contain single-sided shell meshes that are viewed
		// from both sides after basis conversion. Preserve visibility over culling.
		OutRasterState = "SolidNoCull";

		FString BaseTexture;
		FString NormalTexture;
		FString PackedRmoTexture;
		FString EmissiveTexture;
		FString OpacityTexture;
		const FString MaterialIdentity = ToLowerAscii(
			ReadString(MaterialObject, "key") + " " +
			ReadString(MaterialObject, "baseMaterial") + " " +
			ReadString(MaterialObject, "sourceAsset"));
		const bool bDecalMaterial = IsDecalIdentity(MaterialIdentity);
		bool bUseBaseRedForOpacityMask = bMasked && ContainsAny(
			MaterialIdentity,
			{ "trim_text", "m_text", "mi_text" });

		if (MaterialObject.hasKey("textures") &&
			MaterialObject["textures"].JSONType() == json::JSON::Class::Array)
		{
			for (json::JSON& TextureRef : MaterialObject["textures"].ArrayRange())
			{
				const FString TextureKey = ReadString(TextureRef, "texture");
				auto PathIt = TexturePaths.find(TextureKey);
				if (PathIt == TexturePaths.end())
				{
					continue;
				}

				const FString Classifier = ToLowerAscii(
					ReadString(TextureRef, "parameter") + " " +
					TextureKey + " " +
					ReadString(TextureRef, "usageGuess"));
				if (bMasked && ContainsAny(Classifier, { "text" }))
				{
					bUseBaseRedForOpacityMask = true;
				}
				if (ContainsAny(Classifier, { "normal" }))
				{
					NormalTexture = PathIt->second;
				}
				else if (ContainsAny(Classifier, { "emissive", "emission" }))
				{
					EmissiveTexture = PathIt->second;
				}
				else if (ContainsAny(Classifier, { "rmo", "orm", "roughness", "metallic", "metalness" }))
				{
					PackedRmoTexture = PathIt->second;
				}
				else if (ContainsAny(Classifier, { "opacity", "mask" }))
				{
					OpacityTexture = PathIt->second;
					if (BaseTexture.empty())
					{
						BaseTexture = PathIt->second;
					}
				}
				else if (ContainsAny(Classifier, { "base", "albedo", "diffuse", "color" }))
				{
					BaseTexture = PathIt->second;
				}
				else if (BaseTexture.empty())
				{
					BaseTexture = PathIt->second;
				}
			}
		}

		if (bMasked && OpacityTexture.empty() && !BaseTexture.empty())
		{
			OpacityTexture = BaseTexture;
		}

		const bool bProceduralMaskedDecalFallback =
			bDecalMaterial && bMasked && BaseTexture.empty() && OpacityTexture.empty();
		if (bProceduralMaskedDecalFallback)
		{
			// UE decal masters can use procedural masks that are not exported in the manifest.
			// Keep those planes as overlays instead of importing them as opaque geometry.
			OutRenderPass = "AlphaBlend";
			OutBlendState = "AlphaBlend";
			OutDepthState = "DepthReadOnly";
		}

		json::JSON EmptyObject = json::JSON::Make(json::JSON::Class::Object);
		json::JSON& Scalars = MaterialObject.hasKey("scalars") ? MaterialObject["scalars"] : EmptyObject;
		json::JSON& Vectors = MaterialObject.hasKey("vectors") ? MaterialObject["vectors"] : EmptyObject;

		FVector4 BaseColor(1.0f, 1.0f, 1.0f, 1.0f);
		ReadNamedVector(
			Vectors,
			{ "color multiply", "base color", "basecolor", "color", "tint", "glass color" },
			BaseColor);
		BaseColor.W = 1.0f;

		float Roughness = 0.5f;
		float Metallic = 0.0f;
		float Opacity = (bTranslucent || bProceduralMaskedDecalFallback) ? 0.5f : 1.0f;
		ReadNamedScalar(Scalars, { "roughness", "rough" }, Roughness);
		ReadNamedScalar(Scalars, { "metallic", "metalness" }, Metallic);
		ReadNamedScalar(
			Scalars,
			bProceduralMaskedDecalFallback
				? std::initializer_list<const char*>{ "dirt mask opacity", "mask opacity", "opacity" }
				: std::initializer_list<const char*>{ "opacity" },
			Opacity);
		if (bProceduralMaskedDecalFallback)
		{
			Opacity = (std::min)(Opacity, 0.25f);
		}

		float EmissiveIntensity = 0.0f;
		const bool bHasEmissiveIntensity = ReadNamedScalar(
			Scalars,
			{ "light intensity", "emissive intensity", "emissive int" },
			EmissiveIntensity);
		if (!bHasEmissiveIntensity &&
			(!EmissiveTexture.empty() || ContainsAny(MaterialIdentity, { "emissive" })))
		{
			EmissiveIntensity = 1.0f;
		}

		FVector4 EmissiveColor(BaseColor.X, BaseColor.Y, BaseColor.Z, 1.0f);
		ReadNamedVector(
			Vectors,
			{ "light color", "emissive color", "emissivecolor" },
			EmissiveColor);
		EmissiveColor.W = 1.0f;

		OutGraph = FMaterialGraph();
		FMaterialGraphNode* Output =
			OutGraph.AddNodeOfType(EMaterialGraphNodeType::Output, 760.0f, 80.0f, EMaterialDomain::Surface);
		const uint32 OutputNodeId = Output ? Output->NodeId : 0;

		FTextureSamplePins BasePins;
		uint32 BaseColorPin = 0;
		if (!BaseTexture.empty())
		{
			BasePins = AddTextureSample(
				OutGraph,
				BaseTexture,
				EMaterialTextureSlot::Diffuse,
				"Diffuse",
				-760.0f,
				-280.0f);
			BaseColorPin = BasePins.RGB;
			if (!IsNearlyWhite(BaseColor))
			{
				const uint32 TintPin = AddConstant3(OutGraph, BaseColor, -300.0f, -170.0f);
				BaseColorPin = AddMultiply(OutGraph, BaseColorPin, TintPin, 20.0f, -260.0f);
			}
		}
		else
		{
			BaseColorPin = AddConstant3(OutGraph, BaseColor, 20.0f, -260.0f);
		}

		Output = OutGraph.FindNode(OutputNodeId);
		AddGraphLink(
			OutGraph,
			BaseColorPin,
			FindPinId(Output, "BaseColor", EMaterialGraphPinKind::Input));

		if (!NormalTexture.empty())
		{
			const FTextureSamplePins NormalPins = AddTextureSample(
				OutGraph,
				NormalTexture,
				EMaterialTextureSlot::Normal,
				"Normal",
				-760.0f,
				40.0f);
			Output = OutGraph.FindNode(OutputNodeId);
			AddGraphLink(
				OutGraph,
				NormalPins.RGB,
				FindPinId(Output, "Normal", EMaterialGraphPinKind::Input));
		}

		if (!PackedRmoTexture.empty())
		{
			const FTextureSamplePins RmoPins = AddTextureSample(
				OutGraph,
				PackedRmoTexture,
				EMaterialTextureSlot::Roughness,
				"RMO",
				-760.0f,
				350.0f);
			uint32 RoughnessPin = RmoPins.R;
			uint32 MetallicPin = RmoPins.G;
			if (std::abs(Roughness - 1.0f) > 0.0001f)
			{
				RoughnessPin = AddMultiply(
					OutGraph,
					RoughnessPin,
					AddConstant(OutGraph, Roughness, -250.0f, 330.0f),
					20.0f,
					300.0f);
			}
			if (std::abs(Metallic - 1.0f) > 0.0001f)
			{
				MetallicPin = AddMultiply(
					OutGraph,
					MetallicPin,
					AddConstant(OutGraph, Metallic, -250.0f, 460.0f),
					20.0f,
					440.0f);
			}
			Output = OutGraph.FindNode(OutputNodeId);
			AddGraphLink(
				OutGraph,
				RoughnessPin,
				FindPinId(Output, "Roughness", EMaterialGraphPinKind::Input));
			AddGraphLink(
				OutGraph,
				MetallicPin,
				FindPinId(Output, "Metallic", EMaterialGraphPinKind::Input));
		}
		else
		{
			const uint32 RoughnessPin = AddConstant(OutGraph, Roughness, 180.0f, 300.0f);
			Output = OutGraph.FindNode(OutputNodeId);
			AddGraphLink(
				OutGraph,
				RoughnessPin,
				FindPinId(Output, "Roughness", EMaterialGraphPinKind::Input));

			const uint32 MetallicPin = AddConstant(OutGraph, Metallic, 180.0f, 440.0f);
			Output = OutGraph.FindNode(OutputNodeId);
			AddGraphLink(
				OutGraph,
				MetallicPin,
				FindPinId(Output, "Metallic", EMaterialGraphPinKind::Input));
		}

		if (!EmissiveTexture.empty() || EmissiveIntensity > 0.0f)
		{
			uint32 EmissivePin = 0;
			const FVector4 ScaledEmissive(
				EmissiveColor.X * EmissiveIntensity,
				EmissiveColor.Y * EmissiveIntensity,
				EmissiveColor.Z * EmissiveIntensity,
				1.0f);
			if (!EmissiveTexture.empty())
			{
				const FTextureSamplePins EmissivePins = AddTextureSample(
					OutGraph,
					EmissiveTexture,
					EMaterialTextureSlot::Emissive,
					"Emissive",
					-760.0f,
					650.0f);
				EmissivePin = EmissivePins.RGB;
				if (EmissiveIntensity != 1.0f || !IsNearlyWhite(EmissiveColor))
				{
					EmissivePin = AddMultiply(
						OutGraph,
						EmissivePin,
						AddConstant3(OutGraph, ScaledEmissive, -280.0f, 690.0f),
						20.0f,
						650.0f);
				}
			}
			else
			{
				EmissivePin = AddConstant3(OutGraph, ScaledEmissive, 20.0f, 650.0f);
			}

			Output = OutGraph.FindNode(OutputNodeId);
			AddGraphLink(
				OutGraph,
				EmissivePin,
				FindPinId(Output, "Emissive", EMaterialGraphPinKind::Input));
		}

		if (bMasked && !bProceduralMaskedDecalFallback)
		{
			const bool bUseBaseRedMask =
				bUseBaseRedForOpacityMask ||
				ContainsAny(ToLowerAscii(BaseTexture), { "t_text" });
			uint32 MaskPin = (bUseBaseRedMask && BasePins.R != 0)
				? BasePins.R
				: BasePins.A;
			if (!bUseBaseRedMask && !OpacityTexture.empty() && OpacityTexture != BaseTexture)
			{
				MaskPin = AddTextureSample(
					OutGraph,
					OpacityTexture,
					EMaterialTextureSlot::Custom0,
					"OpacityMask",
					-760.0f,
					900.0f).A;
			}
			Output = OutGraph.FindNode(OutputNodeId);
			AddGraphLink(
				OutGraph,
				MaskPin,
				FindPinId(Output, "OpacityMask", EMaterialGraphPinKind::Input));
			if (bDecalMaterial)
			{
				AddGraphLink(
					OutGraph,
					MaskPin,
					FindPinId(Output, "Opacity", EMaterialGraphPinKind::Input));
			}
		}

		if (bTranslucent || bProceduralMaskedDecalFallback)
		{
			uint32 OpacityPin = AddConstant(OutGraph, Opacity, 180.0f, 860.0f);
			if (BasePins.A != 0)
			{
				OpacityPin = AddMultiply(OutGraph, BasePins.A, OpacityPin, 380.0f, 860.0f);
			}
			Output = OutGraph.FindNode(OutputNodeId);
			AddGraphLink(
				OutGraph,
				OpacityPin,
				FindPinId(Output, "Opacity", EMaterialGraphPinKind::Input));
		}

		return OutputNodeId != 0;
	}

	bool ImportMaterials(
		const std::filesystem::path& SourceRoot,
		const std::filesystem::path& DestinationRoot,
		const std::filesystem::path& ManifestPath,
		ID3D11Device* Device,
		bool bReceiveLighting,
		const TSet<FString>& DecalMaterialSources,
		FUnrealSceneImportResult& Result,
		TMap<FString, UMaterial*>& OutMaterials,
		TMap<FString, UMaterial*>* OutDecalMaterials = nullptr)
	{
		const std::filesystem::path MaterialsPath =
			SourceRoot / (ManifestPath.stem().stem().wstring() + L".materials.json");
		if (!std::filesystem::exists(MaterialsPath))
		{
			UE_LOG("UE scene material metadata not found: %s", FPaths::ToUtf8(MaterialsPath.wstring()).c_str());
			return true;
		}

		FString Content;
		if (!ReadFile(MaterialsPath, Content))
		{
			return false;
		}

		json::JSON Root;
		try
		{
			Root = json::JSON::Load(Content);
		}
		catch (const std::exception& Exception)
		{
			UE_LOG("UE scene material metadata parse failed: %s", Exception.what());
			return false;
		}
		if (!Root.hasKey("materials") || !Root.hasKey("textures") ||
			Root["materials"].JSONType() != json::JSON::Class::Array ||
			Root["textures"].JSONType() != json::JSON::Class::Array)
		{
			return false;
		}

		const std::filesystem::path DestinationTextures = DestinationRoot / L"Textures";
		const std::filesystem::path DestinationMaterials = DestinationRoot / L"Materials";
		std::error_code Error;
		std::filesystem::create_directories(DestinationTextures, Error);
		Error.clear();
		std::filesystem::create_directories(DestinationMaterials, Error);
		if (Error)
		{
			return false;
		}

		TMap<FString, FString> TexturePaths;
		for (json::JSON& TextureObject : Root["textures"].ArrayRange())
		{
			const FString Key = ReadString(TextureObject, "key");
			const FString RelativeFile = ReadString(TextureObject, "file");
			const std::filesystem::path RelativePath(FPaths::ToWide(RelativeFile));
			if (Key.empty() || RelativeFile.empty() || !IsSafeRelativePath(RelativePath))
			{
				++Result.FailedTextureCount;
				continue;
			}

			const std::filesystem::path SourceTexture = (SourceRoot / RelativePath).lexically_normal();
			const std::filesystem::path Extension =
				SourceTexture.has_extension() ? SourceTexture.extension() : std::filesystem::path(L".png");
			const std::filesystem::path DestinationTexture =
				DestinationTextures / (FPaths::ToWide(SanitizePathSegment(Key)) + Extension.wstring());
			if (!std::filesystem::exists(SourceTexture) ||
				!CopyFileIfNeeded(SourceTexture, DestinationTexture))
			{
				++Result.FailedTextureCount;
				continue;
			}

			TexturePaths[Key] = FPaths::MakeProjectRelative(
				FPaths::ToUtf8(DestinationTexture.generic_wstring()));
			++Result.TextureCount;
		}

		TMap<FString, json::JSON*> MaterialsBySourceAsset;
		for (json::JSON& MaterialObject : Root["materials"].ArrayRange())
		{
			const FString SourceAsset = ReadString(MaterialObject, "sourceAsset");
			if (!SourceAsset.empty())
			{
				MaterialsBySourceAsset[SourceAsset] = &MaterialObject;
			}
		}

		for (json::JSON& MaterialObject : Root["materials"].ArrayRange())
		{
			const FString Key = ReadString(MaterialObject, "key");
			const FString SourceAsset = ReadString(MaterialObject, "sourceAsset");
			if (Key.empty() || SourceAsset.empty())
			{
				++Result.FailedMaterialCount;
				continue;
			}

			FMaterialGraph Graph;
			FString RenderPass;
			FString BlendState;
			FString DepthState;
			FString RasterState;
			json::JSON EffectiveMaterialObject =
				BuildEffectiveMaterialObject(MaterialObject, MaterialsBySourceAsset);
			if (!BuildMaterialGraph(
				EffectiveMaterialObject,
				TexturePaths,
				Graph,
				RenderPass,
				BlendState,
				DepthState,
				RasterState))
			{
				++Result.FailedMaterialCount;
				continue;
			}

			const std::filesystem::path MaterialFile =
				DestinationMaterials / (FPaths::ToWide(SanitizePathSegment(Key)) + L".mat");
			const FString ProjectRelativeMaterial = FPaths::MakeProjectRelative(
				FPaths::ToUtf8(MaterialFile.generic_wstring()));

			json::JSON GraphJson;
			MaterialGraphAsset::SaveToJson(Graph, GraphJson);

			json::JSON MaterialJson = json::JSON::Make(json::JSON::Class::Object);
			MaterialJson[MatKeys::Version] = 2;
			MaterialJson[MatKeys::MaterialGuid] = MakeMaterialGuid(SourceAsset);
			MaterialJson[MatKeys::PathFileName] = ProjectRelativeMaterial;
			MaterialJson[MatKeys::Domain] = "Surface";
			MaterialJson[MatKeys::RenderPass] = RenderPass;
			MaterialJson[MatKeys::BlendState] = BlendState;
			MaterialJson[MatKeys::DepthStencilState] = DepthState;
			MaterialJson[MatKeys::RasterizerState] = RasterState;
			MaterialJson[MatKeys::GraphShaderMode] = "Generated";
			MaterialJson[MatKeys::GeneratedShaderPath] = "";
			const FString MaterialIdentity = ToLowerAscii(
				Key + " " +
				ReadString(MaterialObject, "baseMaterial") + " " +
				SourceAsset);
			const bool bDecalMaterial = IsDecalIdentity(MaterialIdentity);
			const bool bUsedByDecalActor =
				DecalMaterialSources.find(SourceAsset) != DecalMaterialSources.end();
			const bool bNeedsDecalDomainMaterial = bDecalMaterial || bUsedByDecalActor;
			MaterialJson[MatKeys::ShadingModel] = bDecalMaterial ? "UnLit" : "DefaultLit";
			MaterialJson[MatKeys::ReceiveLighting] =
				bReceiveLighting && !bDecalMaterial;
			MaterialJson[MatKeys::Graph] = std::move(GraphJson);
			MaterialJson[MatKeys::Compiled] = json::JSON::Make(json::JSON::Class::Object);
			MaterialJson[MatKeys::Compiled][MatKeys::Parameters] =
				json::JSON::Make(json::JSON::Class::Object);
			MaterialJson[MatKeys::Compiled][MatKeys::Textures] =
				json::JSON::Make(json::JSON::Class::Object);

			FString CompileError;
			if (!FMaterialManager::Get().CompileMaterialGraph(
					ProjectRelativeMaterial,
					MaterialJson,
					&CompileError) ||
				!FMaterialManager::Get().SaveMaterialJson(ProjectRelativeMaterial, MaterialJson))
			{
				UE_LOG(
					"UE scene material compile failed: %s (%s)",
					Key.c_str(),
					CompileError.c_str());
				++Result.FailedMaterialCount;
				continue;
			}

			FMaterialManager::Get().InvalidateMaterial(ProjectRelativeMaterial);
			UMaterial* Material =
				FMaterialManager::Get().GetOrCreateMaterial(ProjectRelativeMaterial);
			if (!Material)
			{
				++Result.FailedMaterialCount;
				continue;
			}

			OutMaterials[SourceAsset] = Material;
			++Result.MaterialCount;

			if (bNeedsDecalDomainMaterial && OutDecalMaterials)
			{
				FMaterialGraph DecalGraph = Graph;
				DecalGraph.EnsureOutputPinsForDomain(
					EMaterialDomain::Decal,
					EMaterialShadingModel::DefaultLit);

				json::JSON DecalGraphJson;
				MaterialGraphAsset::SaveToJson(DecalGraph, DecalGraphJson);

				const FString DecalKey = Key + "_Decal";
				const std::filesystem::path DecalMaterialFile =
					DestinationMaterials / (FPaths::ToWide(SanitizePathSegment(DecalKey)) + L".mat");
				const FString ProjectRelativeDecalMaterial = FPaths::MakeProjectRelative(
					FPaths::ToUtf8(DecalMaterialFile.generic_wstring()));

				json::JSON DecalMaterialJson = json::JSON::Make(json::JSON::Class::Object);
				DecalMaterialJson[MatKeys::Version] = 2;
				DecalMaterialJson[MatKeys::MaterialGuid] = MakeMaterialGuid(SourceAsset + "|Decal");
				DecalMaterialJson[MatKeys::PathFileName] = ProjectRelativeDecalMaterial;
				DecalMaterialJson[MatKeys::Domain] = "Decal";
				DecalMaterialJson[MatKeys::RenderPass] = "Decal";
				DecalMaterialJson[MatKeys::BlendState] = "AlphaBlend";
				DecalMaterialJson[MatKeys::DepthStencilState] = "DepthReadOnly";
				DecalMaterialJson[MatKeys::RasterizerState] = RasterState;
				DecalMaterialJson[MatKeys::GraphShaderMode] = "Generated";
				DecalMaterialJson[MatKeys::GeneratedShaderPath] = "";
				DecalMaterialJson[MatKeys::ShadingModel] = "DefaultLit";
				DecalMaterialJson[MatKeys::ReceiveLighting] = false;
				DecalMaterialJson[MatKeys::Graph] = std::move(DecalGraphJson);
				DecalMaterialJson[MatKeys::Compiled] = json::JSON::Make(json::JSON::Class::Object);
				DecalMaterialJson[MatKeys::Compiled][MatKeys::Parameters] =
					json::JSON::Make(json::JSON::Class::Object);
				DecalMaterialJson[MatKeys::Compiled][MatKeys::Textures] =
					json::JSON::Make(json::JSON::Class::Object);

				FString DecalCompileError;
				if (!FMaterialManager::Get().CompileMaterialGraph(
						ProjectRelativeDecalMaterial,
						DecalMaterialJson,
						&DecalCompileError) ||
					!FMaterialManager::Get().SaveMaterialJson(
						ProjectRelativeDecalMaterial,
						DecalMaterialJson))
				{
					UE_LOG(
						"UE scene decal material compile failed: %s (%s)",
						DecalKey.c_str(),
						DecalCompileError.c_str());
					++Result.FailedMaterialCount;
					continue;
				}

				FMaterialManager::Get().InvalidateMaterial(ProjectRelativeDecalMaterial);
				UMaterial* DecalMaterial =
					FMaterialManager::Get().GetOrCreateMaterial(ProjectRelativeDecalMaterial);
				if (DecalMaterial)
				{
					(*OutDecalMaterials)[SourceAsset] = DecalMaterial;
					++Result.MaterialCount;
				}
				else
				{
					++Result.FailedMaterialCount;
				}
			}
		}

		return true;
	}

	void ApplyActorMaterials(
		json::JSON& ActorObject,
		UStaticMeshComponent* Component,
		const TMap<FString, UMaterial*>& ImportedMaterials,
		FUnrealSceneImportResult& Result)
	{
		if (!Component ||
			!ActorObject.hasKey("materials") ||
			ActorObject["materials"].JSONType() != json::JSON::Class::Array)
		{
			return;
		}

		const int32 SlotCount = static_cast<int32>(Component->GetOverrideMaterials().size());
		TArray<UMaterial*> ResolvedMaterials;
		for (json::JSON& MaterialValue : ActorObject["materials"].ArrayRange())
		{
			bool bOk = false;
			const FString SourceAsset = MaterialValue.ToString(bOk);
			if (bOk)
			{
				auto MaterialIt = ImportedMaterials.find(SourceAsset);
				if (MaterialIt != ImportedMaterials.end() && MaterialIt->second)
				{
					ResolvedMaterials.push_back(MaterialIt->second);
				}
			}
		}

		if (ResolvedMaterials.empty())
		{
			return;
		}

		for (int32 SlotIndex = 0; SlotIndex < SlotCount; ++SlotIndex)
		{
			UMaterial* Material = SlotIndex < static_cast<int32>(ResolvedMaterials.size())
				? ResolvedMaterials[SlotIndex]
				: ResolvedMaterials.back();
			Component->SetMaterial(SlotIndex, Material);
			++Result.MaterialAssignmentCount;
		}
	}

	UMaterial* ResolveImportedDecalMaterial(
		const FString& SourceAsset,
		const TMap<FString, UMaterial*>& ImportedMaterials,
		const TMap<FString, UMaterial*>& ImportedDecalMaterials)
	{
		auto DecalIt = ImportedDecalMaterials.find(SourceAsset);
		if (DecalIt != ImportedDecalMaterials.end() && DecalIt->second)
		{
			return DecalIt->second;
		}

		auto MaterialIt = ImportedMaterials.find(SourceAsset);
		if (MaterialIt != ImportedMaterials.end() &&
			MaterialIt->second &&
			MaterialIt->second->GetDomain() == EMaterialDomain::Decal)
		{
			return MaterialIt->second;
		}

		return nullptr;
	}

	void ImportDecalActors(
		json::JSON& Root,
		UWorld* World,
		float LocationScale,
		const TMap<FString, UMaterial*>& ImportedMaterials,
		const TMap<FString, UMaterial*>& ImportedDecalMaterials,
		FUnrealSceneImportResult& Result)
	{
		if (!World ||
			!Root.hasKey("decals") ||
			Root["decals"].JSONType() != json::JSON::Class::Array)
		{
			return;
		}

		for (json::JSON& DecalObject : Root["decals"].ArrayRange())
		{
			FVector Location(0.0f, 0.0f, 0.0f);
			FVector RotationEuler(0.0f, 0.0f, 0.0f);
			FVector Scale(1.0f, 1.0f, 1.0f);
			if (!ReadVector3(DecalObject, "location", Location) ||
				!ReadVector3(DecalObject, "rotation", RotationEuler) ||
				!ReadVector3(DecalObject, "scale", Scale))
			{
				++Result.SkippedActorCount;
				continue;
			}

			Location *= LocationScale;
			Scale *= LocationScale;

			FMatrix WorldMatrix = FMatrix::Identity;
			const bool bHasWorldMatrix =
				ReadMatrix4x4(DecalObject, "worldMatrix", WorldMatrix) ||
				ReadMatrix4x4(DecalObject, "matrix", WorldMatrix);
			if (bHasWorldMatrix)
			{
				for (int32 Row = 0; Row < 3; ++Row)
				{
					for (int32 Column = 0; Column < 3; ++Column)
					{
						WorldMatrix.M[Row][Column] *= LocationScale;
					}
				}
				WorldMatrix.M[3][0] *= LocationScale;
				WorldMatrix.M[3][1] *= LocationScale;
				WorldMatrix.M[3][2] *= LocationScale;
			}

			ADecalActor* Actor = World->SpawnActor<ADecalActor>();
			if (!Actor)
			{
				++Result.SkippedActorCount;
				continue;
			}

			Actor->InitDefaultComponents();
			UDecalComponent* Component = Actor->GetDecalComponent();
			if (!Component)
			{
				World->DestroyActor(Actor);
				++Result.SkippedActorCount;
				continue;
			}

			FScenePlacementImportRecord Record;
			Record.ActorObject = &DecalObject;
			Record.Location = Location;
			Record.RotationEuler = RotationEuler;
			Record.Scale = Scale;
			Record.WorldMatrix = WorldMatrix;
			Record.bHasWorldMatrix = bHasWorldMatrix;
			Record.bVisible = ReadBool(DecalObject, "visible", true);

			Actor->SetFName(FName(BuildActorName(DecalObject)));
			ApplyPlacementTransform(Actor, Record);
			Actor->SetVisible(Record.bVisible);
			Component->SetVisibility(Record.bVisible);

			FVector4 Color(1.0f, 1.0f, 1.0f, 1.0f);
			ReadVector4(DecalObject, "color", Color);
			Component->SetColor(Color);

			const FString SourceAsset = ReadString(DecalObject, "material");
			if (UMaterial* Material = ResolveImportedDecalMaterial(
					SourceAsset,
					ImportedMaterials,
					ImportedDecalMaterials))
			{
				Component->SetMaterial(Material);
				++Result.MaterialAssignmentCount;
			}

			++Result.ActorCount;
			++Result.EngineActorCount;
			++Result.DecalActorCount;
		}
	}

	void ImportEnvironmentActors(
		json::JSON& Root,
		UWorld* World,
		float LocationScale,
		FUnrealSceneImportResult& Result)
	{
		if (!World ||
			!Root.hasKey("environment") ||
			Root["environment"].JSONType() != json::JSON::Class::Array)
		{
			return;
		}

		for (json::JSON& EnvironmentObject : Root["environment"].ArrayRange())
		{
			const FString Type = ReadString(EnvironmentObject, "type");
			FVector Location(0.0f, 0.0f, 0.0f);
			FVector RotationEuler(0.0f, 0.0f, 0.0f);
			ReadVector3(EnvironmentObject, "location", Location);
			ReadVector3(EnvironmentObject, "rotation", RotationEuler);
			Location *= LocationScale;

			FVector4 Color(1.0f, 1.0f, 1.0f, 1.0f);
			ReadVector4(EnvironmentObject, "color", Color);
			const float Intensity = ReadFloat(EnvironmentObject, "intensity", 1.0f);
			const bool bVisible = ReadBool(EnvironmentObject, "visible", true);
			const bool bCastShadows = ReadBool(EnvironmentObject, "castShadows", true);

			AActor* SpawnedActor = nullptr;
			if (Type == "DirectionalLight")
			{
				ADirectionalLightActor* Actor = World->SpawnActor<ADirectionalLightActor>();
				if (Actor)
				{
					Actor->InitDefaultComponents();
					if (UDirectionalLightComponent* Component =
						Actor->GetComponentByClass<UDirectionalLightComponent>())
					{
						Component->SetIntensity(Intensity);
						Component->SetLightColor(Color);
						Component->SetLightVisible(bVisible);
						Component->SetCastShadows(bCastShadows);
						SpawnedActor = Actor;
					}
				}
			}
			else if (Type == "AmbientLight")
			{
				AAmbientLightActor* Actor = World->SpawnActor<AAmbientLightActor>();
				if (Actor)
				{
					Actor->InitDefaultComponents();
					if (UAmbientLightComponent* Component =
						Actor->GetComponentByClass<UAmbientLightComponent>())
					{
						Component->SetIntensity(Intensity);
						Component->SetLightColor(Color);
						Component->SetLightVisible(bVisible);
						SpawnedActor = Actor;
					}
				}
			}
			else if (Type == "PointLight")
			{
				APointLightActor* Actor = World->SpawnActor<APointLightActor>();
				if (Actor)
				{
					Actor->InitDefaultComponents();
					if (UPointLightComponent* Component =
						Actor->GetComponentByClass<UPointLightComponent>())
					{
						Component->SetIntensity(Intensity);
						Component->SetLightColor(Color);
						Component->SetLightVisible(bVisible);
						Component->SetCastShadows(bCastShadows);
						Component->SetAttenuationRadius(
							ReadFloat(EnvironmentObject, "attenuationRadius", 10.0f) *
							LocationScale);
						Component->SetLightFalloffExponent(
							ReadFloat(EnvironmentObject, "falloffExponent", 2.0f));
						SpawnedActor = Actor;
					}
				}
			}
			else if (Type == "SpotLight")
			{
				ASpotLightActor* Actor = World->SpawnActor<ASpotLightActor>();
				if (Actor)
				{
					Actor->InitDefaultComponents();
					if (USpotLightComponent* Component =
						Actor->GetComponentByClass<USpotLightComponent>())
					{
						Component->SetIntensity(Intensity);
						Component->SetLightColor(Color);
						Component->SetLightVisible(bVisible);
						Component->SetCastShadows(bCastShadows);
						Component->SetAttenuationRadius(
							ReadFloat(EnvironmentObject, "attenuationRadius", 10.0f) *
							LocationScale);
						Component->SetLightFalloffExponent(
							ReadFloat(EnvironmentObject, "falloffExponent", 2.0f));
						Component->SetConeAngles(
							ReadFloat(EnvironmentObject, "innerConeAngle", 20.0f),
							ReadFloat(EnvironmentObject, "outerConeAngle", 40.0f));
						SpawnedActor = Actor;
					}
				}
			}
			else if (Type == "HeightFog")
			{
				AHeightFogActor* Actor = World->SpawnActor<AHeightFogActor>();
				if (Actor)
				{
					Actor->InitDefaultComponents();
					if (UHeightFogComponent* Component = Actor->GetFogComponent())
					{
						Component->SetFogParameters(
							ReadFloat(EnvironmentObject, "density", 0.02f),
							ReadFloat(EnvironmentObject, "heightFalloff", 0.2f),
							ReadFloat(EnvironmentObject, "startDistance", 0.0f) *
								LocationScale,
							ReadFloat(EnvironmentObject, "cutoffDistance", 0.0f) *
								LocationScale,
							ReadFloat(EnvironmentObject, "maxOpacity", 1.0f),
							Color);
						SpawnedActor = Actor;
					}
				}
			}
			else
			{
				UE_LOG("UE scene import skipped unsupported environment type: %s", Type.c_str());
				continue;
			}

			if (!SpawnedActor)
			{
				++Result.SkippedActorCount;
				continue;
			}

			SpawnedActor->SetFName(FName(BuildActorName(EnvironmentObject)));
			SpawnedActor->SetActorLocation(Location);
			SpawnedActor->SetActorRotation(
				FRotator(RotationEuler.Y, RotationEuler.Z, RotationEuler.X));
			SpawnedActor->SetVisible(bVisible);
			++Result.ActorCount;
			++Result.EngineActorCount;
			++Result.EnvironmentActorCount;
		}
	}

	void CopyOptionalExportMetadata(
		const std::filesystem::path& SourceRoot,
		const std::filesystem::path& DestinationRoot,
		const std::filesystem::path& ManifestPath)
	{
		CopyFileIfNeeded(ManifestPath, DestinationRoot / ManifestPath.filename());

		const std::filesystem::path MaterialsPath =
			SourceRoot / (ManifestPath.stem().stem().wstring() + L".materials.json");
		if (std::filesystem::exists(MaterialsPath))
		{
			CopyFileIfNeeded(MaterialsPath, DestinationRoot / MaterialsPath.filename());
		}
	}
}

FUnrealSceneImportResult FUnrealSceneManifestImporter::Import(
	const FString& ManifestPath,
	UWorld* World,
	ID3D11Device* Device,
	const FUnrealSceneImportOptions& Options)
{
	FUnrealSceneImportResult Result;
	if (!World || !Device)
	{
		Result.ErrorMessage = "No active world or rendering device.";
		return Result;
	}

	const std::filesystem::path ManifestFile(FPaths::ToWide(ManifestPath));
	if (!std::filesystem::exists(ManifestFile))
	{
		Result.ErrorMessage = "Manifest file does not exist.";
		return Result;
	}

	FString FileContent;
	if (!ReadFile(ManifestFile, FileContent))
	{
		Result.ErrorMessage = "Failed to read manifest file.";
		return Result;
	}

	json::JSON Root;
	try
	{
		Root = json::JSON::Load(FileContent);
	}
	catch (const std::exception& Exception)
	{
		Result.ErrorMessage = FString("Failed to parse manifest: ") + Exception.what();
		return Result;
	}

	if (!Root.hasKey("meshes") || !Root.hasKey("actors"))
	{
		Result.ErrorMessage = "Manifest must contain meshes and actors arrays.";
		return Result;
	}
	if (Root["meshes"].JSONType() != json::JSON::Class::Array ||
		Root["actors"].JSONType() != json::JSON::Class::Array)
	{
		Result.ErrorMessage = "Manifest meshes or actors field is not an array.";
		return Result;
	}

	const FString Unit = ReadString(Root, "unit", "meter");
	const float LocationScale = Unit == "centimeter" ? 0.01f : 1.0f;
	if (Unit != "meter" && Unit != "centimeter")
	{
		Result.ErrorMessage = "Unsupported manifest unit. Expected meter or centimeter.";
		return Result;
	}

	const FString CoordinateSystem = ReadString(Root, "coordinateSystem", "leftHandedZUp");
	if (CoordinateSystem != "leftHandedZUp")
	{
		Result.ErrorMessage = "Unsupported coordinate system. Expected leftHandedZUp.";
		return Result;
	}

	const std::filesystem::path SourceRoot = ManifestFile.parent_path();
	const FString ImportName = SanitizePathSegment(
		FPaths::ToUtf8(ManifestFile.stem().stem().wstring()));
	const std::filesystem::path DestinationRoot =
		std::filesystem::path(FPaths::RootDir()) / L"Content" / L"Data" / L"UnrealImport" /
		FPaths::ToWide(ImportName);
	const std::filesystem::path DestinationMeshes = DestinationRoot / L"Meshes";

	std::error_code DirectoryError;
	std::filesystem::create_directories(DestinationMeshes, DirectoryError);
	if (DirectoryError)
	{
		Result.ErrorMessage = "Failed to create the Unreal import destination directory.";
		return Result;
	}

	Result.DestinationDirectory = FPaths::MakeProjectRelative(
		FPaths::ToUtf8(DestinationRoot.generic_wstring()));
	CopyOptionalExportMetadata(SourceRoot, DestinationRoot, ManifestFile);

	TSet<FString> DecalMaterialSources;
	if (Root.hasKey("decals") && Root["decals"].JSONType() == json::JSON::Class::Array)
	{
		for (json::JSON& DecalObject : Root["decals"].ArrayRange())
		{
			const FString SourceAsset = ReadString(DecalObject, "material");
			if (!SourceAsset.empty() && SourceAsset != "None")
			{
				DecalMaterialSources.insert(SourceAsset);
			}
		}
	}

	TMap<FString, UMaterial*> ImportedMaterials;
	TMap<FString, UMaterial*> ImportedDecalMaterials;
	if (!ImportMaterials(
		SourceRoot,
		DestinationRoot,
		ManifestFile,
		Device,
		ReadBool(Root, "materialLighting", false),
		DecalMaterialSources,
		Result,
		ImportedMaterials,
		&ImportedDecalMaterials))
	{
		UE_LOG("UE scene material import could not read the optional material metadata.");
	}

	TMap<FString, UStaticMesh*> ImportedMeshes;
	for (json::JSON& MeshObject : Root["meshes"].ArrayRange())
	{
		const FString Key = ReadString(MeshObject, "key");
		const FString RelativeFbx = ReadString(MeshObject, "fbx");
		if (Key.empty() || RelativeFbx.empty())
		{
			++Result.FailedMeshCount;
			continue;
		}

		const std::filesystem::path RelativePath(FPaths::ToWide(RelativeFbx));
		if (!IsSafeRelativePath(RelativePath))
		{
			UE_LOG("UE scene import skipped unsafe FBX path: %s", RelativeFbx.c_str());
			++Result.FailedMeshCount;
			continue;
		}

		const std::filesystem::path SourceFbx = (SourceRoot / RelativePath).lexically_normal();
		const std::filesystem::path DestinationFbx =
			DestinationMeshes / (FPaths::ToWide(SanitizePathSegment(Key)) + L".fbx");

		if (!std::filesystem::exists(SourceFbx) || !CopyFileIfNeeded(SourceFbx, DestinationFbx))
		{
			UE_LOG("UE scene import failed to copy FBX: %s", FPaths::ToUtf8(SourceFbx.wstring()).c_str());
			++Result.FailedMeshCount;
			continue;
		}

		const FString ProjectRelativeFbx = FPaths::MakeProjectRelative(
			FPaths::ToUtf8(DestinationFbx.generic_wstring()));
		FImportOptions MeshImportOptions = FImportOptions::Default();
		MeshImportOptions.bImportTextures = false;
		MeshImportOptions.bCreateMaterials = false;
		MeshImportOptions.bBakeFbxNodeTransform = true;
		MeshImportOptions.bConvertUnrealFbxCoordinateSystem = true;
		UStaticMesh* Mesh = FMeshManager::LoadStaticMesh(ProjectRelativeFbx, MeshImportOptions, Device);
		if (!Mesh)
		{
			UE_LOG("UE scene import failed to import FBX: %s", ProjectRelativeFbx.c_str());
			++Result.FailedMeshCount;
			continue;
		}

		ImportedMeshes[Key] = Mesh;
		++Result.MeshCount;
	}

	TArray<FScenePlacementImportRecord> PlacementRecords;
	TMap<FString, TArray<int32>> InstancingGroups;
	TArray<FString> InstancingGroupOrder;
	PlacementRecords.reserve(Root["actors"].length());

	World->BeginDeferredPickingBVHUpdate();
	for (json::JSON& ActorObject : Root["actors"].ArrayRange())
	{
		const FString MeshKey = ReadString(ActorObject, "mesh");
		auto MeshIt = ImportedMeshes.find(MeshKey);
		if (MeshIt == ImportedMeshes.end() || !MeshIt->second)
		{
			++Result.SkippedActorCount;
			continue;
		}

		FVector Location;
		FVector RotationEuler;
		FVector Scale(1.0f, 1.0f, 1.0f);
		if (!ReadVector3(ActorObject, "location", Location) ||
			!ReadVector3(ActorObject, "rotation", RotationEuler) ||
			!ReadVector3(ActorObject, "scale", Scale))
		{
			++Result.SkippedActorCount;
			continue;
		}

		Location *= LocationScale;
		FMatrix WorldMatrix = FMatrix::Identity;
		const bool bHasWorldMatrix =
			ReadMatrix4x4(ActorObject, "worldMatrix", WorldMatrix) ||
			ReadMatrix4x4(ActorObject, "matrix", WorldMatrix);
		if (bHasWorldMatrix)
		{
			WorldMatrix.M[3][0] *= LocationScale;
			WorldMatrix.M[3][1] *= LocationScale;
			WorldMatrix.M[3][2] *= LocationScale;
		}

		FScenePlacementImportRecord Record;
		Record.ActorObject = &ActorObject;
		Record.Mesh = MeshIt->second;
		Record.MeshKey = MeshKey;
		Record.Location = Location;
		Record.RotationEuler = RotationEuler;
		Record.Scale = Scale;
		Record.WorldMatrix = WorldMatrix;
		Record.bHasWorldMatrix = bHasWorldMatrix;
		Record.CollisionString = ReadString(ActorObject, "collision");
		Record.Collision = ParseCollisionMode(Record.CollisionString);
		Record.bVisible = ReadBool(ActorObject, "visible", true);
		Record.bCastShadow = ReadBool(ActorObject, "castShadow", true);
		const FString ActorIdentity = ToLowerAscii(
			MeshKey + " " +
			ReadString(ActorObject, "name") + " " +
			ReadString(ActorObject, "sourceAsset"));
		if (IsDecalIdentity(ActorIdentity))
		{
			Record.bCastShadow = false;
		}
		Record.bNegativeScale = Scale.X < 0.0f || Scale.Y < 0.0f || Scale.Z < 0.0f;
		if (Record.bHasWorldMatrix)
		{
			++Result.MatrixTransformCount;
		}

		if (Record.bNegativeScale)
		{
			++Result.NegativeScaleCount;
		}

		const int32 RecordIndex = static_cast<int32>(PlacementRecords.size());
		if (Options.bOptimizeStaticMeshInstances && !Record.bNegativeScale)
		{
			Record.GroupKey = BuildInstancingGroupKey(
				Record,
				BuildMaterialSignature(ActorObject));
			TArray<int32>& Group = InstancingGroups[Record.GroupKey];
			if (Group.empty())
			{
				InstancingGroupOrder.push_back(Record.GroupKey);
			}
			Group.push_back(RecordIndex);
		}

		PlacementRecords.push_back(std::move(Record));
	}

	TArray<bool> bConsumed;
	bConsumed.resize(PlacementRecords.size(), false);
	if (Options.bOptimizeStaticMeshInstances)
	{
		constexpr int32 MinInstancedPlacements = 2;
		int32 InstancedGroupIndex = 0;
		for (const FString& GroupKey : InstancingGroupOrder)
		{
			const auto GroupIt = InstancingGroups.find(GroupKey);
			if (GroupIt == InstancingGroups.end() ||
				static_cast<int32>(GroupIt->second.size()) < MinInstancedPlacements)
			{
				continue;
			}

			if (SpawnInstancedStaticMeshGroup(
					World,
					PlacementRecords,
					GroupIt->second,
					InstancedGroupIndex,
					ImportedMaterials,
					Result))
			{
				for (int32 Index : GroupIt->second)
				{
					bConsumed[Index] = true;
				}
				++InstancedGroupIndex;
			}
		}
	}

	for (int32 Index = 0; Index < static_cast<int32>(PlacementRecords.size()); ++Index)
	{
		if (!bConsumed[Index])
		{
			SpawnStaticMeshPlacement(
				World,
				PlacementRecords[Index],
				ImportedMaterials,
				Result);
		}
	}
	ImportDecalActors(
		Root,
		World,
		LocationScale,
		ImportedMaterials,
		ImportedDecalMaterials,
		Result);
	ImportEnvironmentActors(Root, World, LocationScale, Result);
	World->EndDeferredPickingBVHUpdate();

	Result.bSuccess = Result.ActorCount > 0;
	if (!Result.bSuccess && Result.ErrorMessage.empty())
	{
		Result.ErrorMessage = "No actors were imported.";
	}

	UE_LOG(
		"UE scene import complete. Meshes=%d Placements=%d EngineActors=%d InstancedGroups=%d "
		"InstancedPlacements=%d MatrixTransforms=%d CorrectedMatrixTransforms=%d "
		"Environment=%d Decals=%d Textures=%d Materials=%d MaterialSlots=%d "
		"FailedMeshes=%d FailedTextures=%d FailedMaterials=%d SkippedActors=%d NegativeScale=%d",
		Result.MeshCount,
		Result.ActorCount,
		Result.EngineActorCount,
		Result.InstancedGroupCount,
		Result.InstancedPlacementCount,
		Result.MatrixTransformCount,
		Result.CorrectedMatrixTransformCount,
		Result.EnvironmentActorCount,
		Result.DecalActorCount,
		Result.TextureCount,
		Result.MaterialCount,
		Result.MaterialAssignmentCount,
		Result.FailedMeshCount,
		Result.FailedTextureCount,
		Result.FailedMaterialCount,
		Result.SkippedActorCount,
		Result.NegativeScaleCount);
	return Result;
}
