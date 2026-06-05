#include "Mesh/Importer/Fbx/FbxSkeletonImporter.h"
#include "Mesh/Importer/Fbx/FbxSceneQuery.h"
#include "Mesh/Importer/Fbx/FbxTransformUtils.h"

namespace
{
	static void CollectSkinClusterLinkNodes(FFbxImportContext& Context, TSet<FbxNode*>& OutNodes)
	{
		for (FbxNode* Node : Context.AllNodes)
		{
			FbxMesh* Mesh = Node ? Node->GetMesh() : nullptr;
			if (!Mesh)
			{
				continue;
			}

			const int32 DeformerCount = Mesh->GetDeformerCount(FbxDeformer::eSkin);
			for (int32 DeformerIndex = 0; DeformerIndex < DeformerCount; ++DeformerIndex)
			{
				FbxSkin* Skin = static_cast<FbxSkin*>(Mesh->GetDeformer(DeformerIndex, FbxDeformer::eSkin));
				if (!Skin)
				{
					continue;
				}

				for (int32 ClusterIndex = 0; ClusterIndex < Skin->GetClusterCount(); ++ClusterIndex)
				{
					FbxCluster* Cluster = Skin->GetCluster(ClusterIndex);
					FbxNode*    LinkNode = Cluster ? Cluster->GetLink() : nullptr;
					if (LinkNode)
					{
						OutNodes.insert(LinkNode);
					}
				}
			}
		}
	}

	static bool IsBaseBoneNode(FbxNode* Node, const TSet<FbxNode*>& SkinClusterLinkNodes)
	{
		return FFbxSceneQuery::IsSkeletonNode(Node) || SkinClusterLinkNodes.find(Node) != SkinClusterLinkNodes.end();
	}

	static bool BuildBaseBoneDescendantCache(
		FbxNode*                    Node,
		const TSet<FbxNode*>&       SkinClusterLinkNodes,
		TMap<FbxNode*, bool>&       OutHasBaseBoneDescendant
		)
	{
		if (!Node)
		{
			return false;
		}

		bool bHasBaseBone = IsBaseBoneNode(Node, SkinClusterLinkNodes);
		for (int32 ChildIndex = 0; ChildIndex < Node->GetChildCount(); ++ChildIndex)
		{
			bHasBaseBone |= BuildBaseBoneDescendantCache(Node->GetChild(ChildIndex), SkinClusterLinkNodes, OutHasBaseBoneDescendant);
		}

		OutHasBaseBoneDescendant[Node] = bHasBaseBone;
		return bHasBaseBone;
	}

	static bool ContainsBaseBoneDescendant(FbxNode* Node, const TMap<FbxNode*, bool>& BaseBoneDescendantCache)
	{
		auto It = BaseBoneDescendantCache.find(Node);
		return It != BaseBoneDescendantCache.end() && It->second;
	}

	static bool IsVirtualLcaNode(
		FbxNode*                    Node,
		const TSet<FbxNode*>&       SkinClusterLinkNodes,
		const TMap<FbxNode*, bool>& BaseBoneDescendantCache
		)
	{
		if (!Node || !Node->GetParent() || IsBaseBoneNode(Node, SkinClusterLinkNodes))
		{
			return false;
		}

		int32 BoneChildBranchCount = 0;
		for (int32 ChildIndex = 0; ChildIndex < Node->GetChildCount(); ++ChildIndex)
		{
			if (ContainsBaseBoneDescendant(Node->GetChild(ChildIndex), BaseBoneDescendantCache))
			{
				++BoneChildBranchCount;
			}
		}

		return BoneChildBranchCount >= 2;
	}

	static void IncludeDescendantPathsToBaseBones(
		FbxNode*                    Node,
		const TSet<FbxNode*>&       SkinClusterLinkNodes,
		const TMap<FbxNode*, bool>& BaseBoneDescendantCache,
		TSet<FbxNode*>&             InOutIncludedNodes
		)
	{
		if (!Node || !ContainsBaseBoneDescendant(Node, BaseBoneDescendantCache))
		{
			return;
		}

		if (Node->GetParent())
		{
			InOutIncludedNodes.insert(Node);
		}

		if (IsBaseBoneNode(Node, SkinClusterLinkNodes))
		{
			return;
		}

		for (int32 ChildIndex = 0; ChildIndex < Node->GetChildCount(); ++ChildIndex)
		{
			FbxNode* Child = Node->GetChild(ChildIndex);
			if (ContainsBaseBoneDescendant(Child, BaseBoneDescendantCache))
			{
				IncludeDescendantPathsToBaseBones(Child, SkinClusterLinkNodes, BaseBoneDescendantCache, InOutIncludedNodes);
			}
		}
	}

	static void IncludeBridgeToNearestIncludedAncestor(FbxNode* Node, TSet<FbxNode*>& InOutIncludedNodes)
	{
		TArray<FbxNode*> BridgeNodes;
		for (FbxNode* Parent = Node ? Node->GetParent() : nullptr; Parent; Parent = Parent->GetParent())
		{
			if (InOutIncludedNodes.find(Parent) != InOutIncludedNodes.end())
			{
				for (FbxNode* BridgeNode : BridgeNodes)
				{
					InOutIncludedNodes.insert(BridgeNode);
				}
				return;
			}

			if (!Parent->GetParent())
			{
				return;
			}

			BridgeNodes.push_back(Parent);
		}
	}

	static void BuildIncludedBoneNodeSet(FFbxImportContext& Context, TSet<FbxNode*>& OutIncludedNodes)
	{
		OutIncludedNodes.clear();

		TSet<FbxNode*> SkinClusterLinkNodes;
		CollectSkinClusterLinkNodes(Context, SkinClusterLinkNodes);

		TMap<FbxNode*, bool> HasBaseBoneDescendant;
		for (FbxNode* Node : Context.AllNodes)
		{
			if (Node && !Node->GetParent())
			{
				BuildBaseBoneDescendantCache(Node, SkinClusterLinkNodes, HasBaseBoneDescendant);
				break;
			}
		}

		for (FbxNode* Node : Context.AllNodes)
		{
			if (IsBaseBoneNode(Node, SkinClusterLinkNodes))
			{
				OutIncludedNodes.insert(Node);
			}
			else if (IsVirtualLcaNode(Node, SkinClusterLinkNodes, HasBaseBoneDescendant))
			{
				OutIncludedNodes.insert(Node);
			}
		}

		TArray<FbxNode*> NonSkeletonIncludedNodes;
		for (FbxNode* Node : Context.AllNodes)
		{
			if (OutIncludedNodes.find(Node) != OutIncludedNodes.end() && !FFbxSceneQuery::IsSkeletonNode(Node))
			{
				NonSkeletonIncludedNodes.push_back(Node);
			}
		}

		for (FbxNode* IncludedNode : NonSkeletonIncludedNodes)
		{
			IncludeBridgeToNearestIncludedAncestor(IncludedNode, OutIncludedNodes);
			IncludeDescendantPathsToBaseBones(IncludedNode, SkinClusterLinkNodes, HasBaseBoneDescendant, OutIncludedNodes);
		}
	}

	static void BuildReferenceSkeleton(FFbxImportContext& Context)
	{
		Context.ReferenceSkeleton.Bones.clear();
		Context.ReferenceSkeleton.Bones.reserve(Context.Bones.size());

		for (const FBone& Bone : Context.Bones)
		{
			FReferenceBone RefBone;
			RefBone.Name = Bone.Name;
			RefBone.ParentIndex = Bone.ParentIndex;
			RefBone.LocalBindPose = Bone.GetReferenceLocalPose();
			RefBone.GlobalBindPose = Bone.GetReferenceGlobalPose();
			RefBone.InverseBindPose = Bone.GetInverseBindPose();
			RefBone.bOverrideTranslationRetargetMode = Bone.bOverrideTranslationRetargetMode;
			RefBone.TranslationRetargetMode = Bone.TranslationRetargetMode;
			Context.ReferenceSkeleton.Bones.push_back(RefBone);
		}
	}
}

bool FFbxSkeletonImporter::ImportSkeleton(FbxScene* Scene, FFbxImportContext& Context, FString* OutMessage)
{
	(void)Scene;
	Context.Bones.clear();
	Context.BoneNodeToIndex.clear();
	Context.ReferenceSkeleton.Bones.clear();

	TSet<FbxNode*> IncludedBoneNodes;
	BuildIncludedBoneNodeSet(Context, IncludedBoneNodes);

	for (FbxNode* Node : Context.AllNodes)
	{
		if (IncludedBoneNodes.find(Node) == IncludedBoneNodes.end())
		{
			continue;
		}

		FBone Bone;
		Bone.Name = Node->GetName();

		Bone.ParentIndex = FindNearestParentBoneIndex(Node, Context.BoneNodeToIndex);

		const FbxAMatrix GlobalFbxMatrix = Node->EvaluateGlobalTransform();
		const bool bAbsorbWrapperTransform = Bone.ParentIndex < 0 && FFbxSceneQuery::HasNonSkeletonWrapperParent(Node);
		const FbxAMatrix LocalFbxMatrix = bAbsorbWrapperTransform
			? GlobalFbxMatrix
			: Node->EvaluateLocalTransform();
		Bone.LocalMatrix = FFbxTransformUtils::ToEngineMatrix(LocalFbxMatrix);
		Bone.GlobalMatrix = FFbxTransformUtils::ToEngineMatrix(GlobalFbxMatrix);
		Bone.InverseBindPoseMatrix = FFbxTransformUtils::ToEngineInverseMatrix(GlobalFbxMatrix);
		Bone.SyncSeparatedPoseDataFromLegacy();

		const int32 NewBoneIndex = static_cast<int32>(Context.Bones.size());
		Context.Bones.push_back(Bone);
		Context.BoneNodeToIndex[Node] = NewBoneIndex;
	}

	if (Context.Bones.empty())
	{
		if (OutMessage) *OutMessage = "FBX skeletal import failed: no skeleton nodes found.";
		return false;
	}

	BuildReferenceSkeleton(Context);
	return true;
}

int32 FFbxSkeletonImporter::FindNearestParentBoneIndex(FbxNode* Node, const TMap<FbxNode*, int32>& NodeToIndex)
{
	FbxNode* Parent = Node ? Node->GetParent() : nullptr;
	while (Parent)
	{
		auto It = NodeToIndex.find(Parent);
		if (It != NodeToIndex.end())
		{
			return It->second;
		}

		Parent = Parent->GetParent();
	}

	return -1;
}
