#include "Editor/UI/Asset/RmlUi/RmlUiEditorWidget.h"

#include "Asset/AssetPackage.h"
#include "Platform/Paths.h"
#include "UI/RmlUiDocumentAsset.h"
#include "UI/RmlUiDocumentManager.h"

#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <cwctype>
#include <filesystem>
#include <fstream>
#include <imgui.h>
#include <sstream>

namespace
{
	using EWidgetType = FRmlUiEditorWidget::EDesignerWidgetType;
	using ESlotLayout = FRmlUiEditorWidget::EDesignerSlotLayout;
	using ESizeRule = FRmlUiEditorWidget::EDesignerSizeRule;
	using EAnimProperty = FRmlUiEditorWidget::EDesignerAnimProperty;
	using FDesignerNode = FRmlUiEditorWidget::FDesignerNode;
	using FDesignerColor = FRmlUiEditorWidget::FDesignerColor;
	using FDesignerAnimation = FRmlUiEditorWidget::FDesignerAnimation;
	using FDesignerTrack = FRmlUiEditorWidget::FDesignerTrack;
	using FDesignerKeyframe = FRmlUiEditorWidget::FDesignerKeyframe;

	float ClampFloat(float Value, float MinValue, float MaxValue)
	{
		return (std::max)(MinValue, (std::min)(Value, MaxValue));
	}

	bool IsRmlDocumentPath(const FString& Path)
	{
		return FAssetPackage::IsAssetPackagePath(Path);
	}

	std::filesystem::path ResolvePath(const FString& Path)
	{
		std::filesystem::path FilePath(FPaths::ToWide(Path));
		if (!FilePath.is_absolute())
		{
			FilePath = std::filesystem::path(FPaths::RootDir()) / FilePath;
		}
		return FilePath.lexically_normal();
	}

	bool IsNameChar(char C)
	{
		const unsigned char Ch = static_cast<unsigned char>(C);
		return std::isalnum(Ch) || C == '_' || C == '-' || C == ':';
	}

	void AppendUnique(TArray<FString>& Values, const FString& Value)
	{
		if (!Value.empty() && std::find(Values.begin(), Values.end(), Value) == Values.end())
		{
			Values.push_back(Value);
		}
	}

	FString ReadAttributeValue(const std::string& Text, size_t AttrNameEnd)
	{
		size_t Pos = AttrNameEnd;
		while (Pos < Text.size() && std::isspace(static_cast<unsigned char>(Text[Pos])))
		{
			++Pos;
		}
		if (Pos >= Text.size() || Text[Pos] != '=')
		{
			return {};
		}
		++Pos;
		while (Pos < Text.size() && std::isspace(static_cast<unsigned char>(Text[Pos])))
		{
			++Pos;
		}
		if (Pos >= Text.size() || (Text[Pos] != '"' && Text[Pos] != '\''))
		{
			return {};
		}

		const char Quote = Text[Pos++];
		const size_t Begin = Pos;
		while (Pos < Text.size() && Text[Pos] != Quote)
		{
			++Pos;
		}
		return Text.substr(Begin, Pos - Begin);
	}

	FString GetAttributeValue(const std::string& TagText, const char* AttrName)
	{
		const size_t AttrLen = std::strlen(AttrName);
		size_t Pos = 0;
		while ((Pos = TagText.find(AttrName, Pos)) != std::string::npos)
		{
			const bool bBeforeOk = Pos == 0 || !IsNameChar(TagText[Pos - 1]);
			const bool bAfterOk = Pos + AttrLen >= TagText.size() || !IsNameChar(TagText[Pos + AttrLen]);
			if (bBeforeOk && bAfterOk)
			{
				return ReadAttributeValue(TagText, Pos + AttrLen);
			}
			Pos += AttrLen;
		}
		return {};
	}

	void CollectElementIds(const std::string& Text, TArray<FString>& OutIds)
	{
		size_t Pos = 0;
		while ((Pos = Text.find("id", Pos)) != std::string::npos)
		{
			const bool bBeforeOk = Pos == 0 || !IsNameChar(Text[Pos - 1]);
			const bool bAfterOk = Pos + 2 >= Text.size() || !IsNameChar(Text[Pos + 2]);
			if (bBeforeOk && bAfterOk)
			{
				AppendUnique(OutIds, ReadAttributeValue(Text, Pos + 2));
			}
			Pos += 2;
		}
	}

	void AnalyseRmlSource(
		const std::string& Text,
		TArray<FRmlUiEditorWidget::FElementInfo>& OutElements,
		TArray<FString>& OutIds)
	{
		OutElements.clear();
		OutIds.clear();

		int32 Depth = 0;
		size_t Pos = 0;
		while ((Pos = Text.find('<', Pos)) != std::string::npos)
		{
			if (Pos + 1 >= Text.size())
			{
				break;
			}

			const char Next = Text[Pos + 1];
			if (Next == '!' || Next == '?')
			{
				const size_t End = Text.find('>', Pos + 1);
				Pos = End == std::string::npos ? Text.size() : End + 1;
				continue;
			}

			const bool bClosing = Next == '/';
			size_t NamePos = Pos + (bClosing ? 2 : 1);
			while (NamePos < Text.size() && std::isspace(static_cast<unsigned char>(Text[NamePos])))
			{
				++NamePos;
			}

			const size_t NameBegin = NamePos;
			while (NamePos < Text.size() && IsNameChar(Text[NamePos]))
			{
				++NamePos;
			}
			if (NamePos == NameBegin)
			{
				++Pos;
				continue;
			}

			const size_t End = Text.find('>', NamePos);
			if (End == std::string::npos)
			{
				break;
			}

			const bool bSelfClosing = !bClosing && End > Pos && Text[End - 1] == '/';
			if (bClosing)
			{
				Depth = (std::max)(0, Depth - 1);
			}

			const std::string TagBody = Text.substr(NamePos, End - NamePos);
			FRmlUiEditorWidget::FElementInfo Info;
			Info.Tag = Text.substr(NameBegin, NamePos - NameBegin);
			Info.Id = GetAttributeValue(TagBody, "id");
			Info.Depth = Depth;
			Info.bClosing = bClosing;
			Info.bSelfClosing = bSelfClosing;
			OutElements.push_back(Info);
			AppendUnique(OutIds, Info.Id);

			if (!bClosing && !bSelfClosing)
			{
				++Depth;
			}

			Pos = End + 1;
		}

		CollectElementIds(Text, OutIds);
	}

	const char* TypeLabel(EWidgetType Type)
	{
		switch (Type)
		{
		case EWidgetType::Canvas: return "Canvas";
		case EWidgetType::Panel: return "Panel";
		case EWidgetType::Text: return "Text";
		case EWidgetType::Button: return "Button";
		case EWidgetType::Image: return "Image";
		case EWidgetType::ProgressBar: return "ProgressBar";
		case EWidgetType::InputText: return "InputText";
		case EWidgetType::CheckBox: return "CheckBox";
		case EWidgetType::Slider: return "Slider";
		case EWidgetType::List: return "List";
		case EWidgetType::Custom: return "Custom";
		default: return "Widget";
		}
	}

	const char* DefaultTagForType(EWidgetType Type)
	{
		switch (Type)
		{
		case EWidgetType::Button: return "button";
		case EWidgetType::Image: return "img";
		case EWidgetType::InputText: return "input";
		case EWidgetType::CheckBox: return "input";
		default: return "div";
		}
	}

	const char* SlotLayoutLabel(ESlotLayout Layout)
	{
		switch (Layout)
		{
		case ESlotLayout::Canvas: return "Canvas";
		case ESlotLayout::Overlay: return "Overlay";
		case ESlotLayout::HorizontalBox: return "HorizontalBox";
		case ESlotLayout::VerticalBox: return "VerticalBox";
		case ESlotLayout::Grid: return "Grid";
		default: return "Canvas";
		}
	}

	const char* SizeRuleLabel(ESizeRule Rule)
	{
		switch (Rule)
		{
		case ESizeRule::Auto: return "Auto";
		case ESizeRule::Fill: return "Fill";
		default: return "Auto";
		}
	}

	const char* AnimPropertyLabel(EAnimProperty Property)
	{
		switch (Property)
		{
		case EAnimProperty::Opacity: return "Opacity";
		case EAnimProperty::X: return "X";
		case EAnimProperty::Y: return "Y";
		case EAnimProperty::Width: return "Width";
		case EAnimProperty::Height: return "Height";
		case EAnimProperty::Rotation: return "Rotation";
		case EAnimProperty::Scale: return "Scale";
		default: return "Opacity";
		}
	}

	const char* CssPropertyName(EAnimProperty Property)
	{
		switch (Property)
		{
		case EAnimProperty::Opacity: return "opacity";
		case EAnimProperty::X: return "left";
		case EAnimProperty::Y: return "top";
		case EAnimProperty::Width: return "width";
		case EAnimProperty::Height: return "height";
		case EAnimProperty::Rotation: return "transform";
		case EAnimProperty::Scale: return "transform";
		default: return "opacity";
		}
	}

	FString CssAnimatedValue(EAnimProperty Property, float Value)
	{
		char Buffer[96];
		switch (Property)
		{
		case EAnimProperty::Opacity:
			std::snprintf(Buffer, sizeof(Buffer), "%.3f", Value);
			break;
		case EAnimProperty::Rotation:
			std::snprintf(Buffer, sizeof(Buffer), "rotate(%.3fdeg)", Value);
			break;
		case EAnimProperty::Scale:
			std::snprintf(Buffer, sizeof(Buffer), "scale(%.3f)", Value);
			break;
		default:
			std::snprintf(Buffer, sizeof(Buffer), "%.3fpx", Value);
			break;
		}
		return Buffer;
	}

	const char* AnimationIteration(bool bLoop)
	{
		return bLoop ? "infinite" : "1";
	}

	ImU32 ToImColor(const FDesignerColor& Color)
	{
		return IM_COL32(
			static_cast<int>(ClampFloat(Color.R, 0.0f, 1.0f) * 255.0f),
			static_cast<int>(ClampFloat(Color.G, 0.0f, 1.0f) * 255.0f),
			static_cast<int>(ClampFloat(Color.B, 0.0f, 1.0f) * 255.0f),
			static_cast<int>(ClampFloat(Color.A, 0.0f, 1.0f) * 255.0f)
		);
	}

	FString EscapeHtml(const FString& In)
	{
		FString Out;
		Out.reserve(In.size());
		for (char C : In)
		{
			switch (C)
			{
			case '&': Out += "&amp;"; break;
			case '<': Out += "&lt;"; break;
			case '>': Out += "&gt;"; break;
			case '"': Out += "&quot;"; break;
			default: Out.push_back(C); break;
			}
		}
		return Out;
	}

	FString CssColor(const FDesignerColor& Color)
	{
		char Buffer[96];
		std::snprintf(
			Buffer,
			sizeof(Buffer),
			"rgba(%d, %d, %d, %.3f)",
			static_cast<int>(ClampFloat(Color.R, 0.0f, 1.0f) * 255.0f),
			static_cast<int>(ClampFloat(Color.G, 0.0f, 1.0f) * 255.0f),
			static_cast<int>(ClampFloat(Color.B, 0.0f, 1.0f) * 255.0f),
			ClampFloat(Color.A, 0.0f, 1.0f)
		);
		return Buffer;
	}

	FString CssIdentifier(const FString& In)
	{
		FString Out;
		Out.reserve(In.size() + 8);
		for (char C : In)
		{
			const unsigned char Ch = static_cast<unsigned char>(C);
			Out.push_back(std::isalnum(Ch) ? C : '_');
		}
		if (Out.empty() || std::isdigit(static_cast<unsigned char>(Out[0])))
		{
			Out = FString("rml_") + Out;
		}
		return Out;
	}

	FString EscapeStateString(const FString& In)
	{
		FString Out;
		Out.reserve(In.size());
		for (char C : In)
		{
			switch (C)
			{
			case '\\': Out += "\\\\"; break;
			case '\t': Out += "\\t"; break;
			case '\n': Out += "\\n"; break;
			case '\r': Out += "\\r"; break;
			default: Out.push_back(C); break;
			}
		}
		return Out;
	}

	FString UnescapeStateString(const FString& In)
	{
		FString Out;
		Out.reserve(In.size());
		for (size_t Index = 0; Index < In.size(); ++Index)
		{
			const char C = In[Index];
			if (C != '\\' || Index + 1 >= In.size())
			{
				Out.push_back(C);
				continue;
			}

			const char Next = In[++Index];
			switch (Next)
			{
			case '\\': Out.push_back('\\'); break;
			case 't': Out.push_back('\t'); break;
			case 'n': Out.push_back('\n'); break;
			case 'r': Out.push_back('\r'); break;
			default:
				Out.push_back('\\');
				Out.push_back(Next);
				break;
			}
		}
		return Out;
	}

	TArray<FString> SplitStateFields(const FString& Line)
	{
		TArray<FString> Fields;
		size_t Begin = 0;
		for (;;)
		{
			const size_t Tab = Line.find('\t', Begin);
			if (Tab == FString::npos)
			{
				Fields.push_back(Line.substr(Begin));
				break;
			}
			Fields.push_back(Line.substr(Begin, Tab - Begin));
			Begin = Tab + 1;
		}
		return Fields;
	}

	int32 StateInt(const TArray<FString>& Fields, size_t Index, int32 Fallback = 0)
	{
		return Index < Fields.size() ? static_cast<int32>(std::strtol(Fields[Index].c_str(), nullptr, 10)) : Fallback;
	}

	float StateFloat(const TArray<FString>& Fields, size_t Index, float Fallback = 0.0f)
	{
		return Index < Fields.size() ? std::strtof(Fields[Index].c_str(), nullptr) : Fallback;
	}

	FString StateString(const TArray<FString>& Fields, size_t Index)
	{
		return Index < Fields.size() ? UnescapeStateString(Fields[Index]) : FString();
	}

	void Indent(std::ostringstream& Out, int32 Depth)
	{
		for (int32 Index = 0; Index < Depth; ++Index)
		{
			Out << "    ";
		}
	}

	bool InputFString(const char* Label, FString& Value)
	{
		char Buffer[512];
		std::snprintf(Buffer, sizeof(Buffer), "%s", Value.c_str());
		if (ImGui::InputText(Label, Buffer, sizeof(Buffer)))
		{
			Value = Buffer;
			return true;
		}
		return false;
	}

	bool ColorEdit(const char* Label, FDesignerColor& Color)
	{
		float Values[4] = { Color.R, Color.G, Color.B, Color.A };
		if (ImGui::ColorEdit4(Label, Values))
		{
			Color.R = Values[0];
			Color.G = Values[1];
			Color.B = Values[2];
			Color.A = Values[3];
			return true;
		}
		return false;
	}

	float ExtractCssPx(const FString& Style, const char* Property, float Fallback)
	{
		const size_t Pos = Style.find(Property);
		if (Pos == FString::npos)
		{
			return Fallback;
		}
		const size_t Colon = Style.find(':', Pos);
		if (Colon == FString::npos)
		{
			return Fallback;
		}
		return static_cast<float>(std::atof(Style.c_str() + Colon + 1));
	}

	EWidgetType TypeFromTag(const FString& Tag, const FString& ClassName)
	{
		if (Tag == "button") return EWidgetType::Button;
		if (Tag == "img") return EWidgetType::Image;
		if (Tag == "input") return ClassName.find("check") != FString::npos ? EWidgetType::CheckBox : EWidgetType::InputText;
		if (ClassName.find("progress") != FString::npos || ClassName.find("bar") != FString::npos) return EWidgetType::ProgressBar;
		return EWidgetType::Panel;
	}

	const char* DefaultRmlTemplate =
		"<rml>\n"
		"<head>\n"
		"    <title>HUD</title>\n"
		"    <style>\n"
		"        body { width: 100%; height: 100%; margin: 0; font-family: Maplestory; }\n"
		"    </style>\n"
		"</head>\n"
		"<body>\n"
		"    <div id=\"root\"></div>\n"
		"</body>\n"
		"</rml>\n";
}

bool FRmlUiEditorWidget::CanEdit(UObject* Object) const
{
	const URmlUiDocumentAsset* Asset = Cast<URmlUiDocumentAsset>(Object);
	return Asset && IsRmlDocumentPath(Asset->GetSourcePath());
}

bool FRmlUiEditorWidget::IsEditingObject(UObject* Object) const
{
	const URmlUiDocumentAsset* Current = GetDocumentAsset();
	const URmlUiDocumentAsset* Other = Cast<URmlUiDocumentAsset>(Object);
	return IsOpen() && Current && Other && Current->GetSourcePath() == Other->GetSourcePath();
}

void FRmlUiEditorWidget::Open(UObject* Object)
{
	if (!CanEdit(Object))
	{
		return;
	}

	FAssetEditorWidget::Open(Object);
	LoadFromDisk();
}

void FRmlUiEditorWidget::Close()
{
	SourceBuffer.clear();
	Elements.clear();
	ElementIds.clear();
	ClearDesignerModel();
	UndoStack.clear();
	RedoStack.clear();
	LastError.clear();
	StatusMessage.clear();
	bLoaded = false;
	bAnalysisDirty = true;
	bDesignerDirty = true;
	FAssetEditorWidget::Close();
}

void FRmlUiEditorWidget::Render(float /*DeltaTime*/)
{
	URmlUiDocumentAsset* Asset = GetDocumentAsset();
	if (!Asset)
	{
		Close();
		return;
	}

	const FString DirtyMark = IsDirty() ? "*" : "";
	char WindowTitle[512];
	std::snprintf(
		WindowTitle,
		sizeof(WindowTitle),
		"RmlUi Designer - %s%s###RmlUi_%p",
		Asset->GetSourcePath().c_str(),
		DirtyMark.c_str(),
		static_cast<void*>(Asset)
	);

	bool bWindowOpen = IsOpen();
	ImGui::SetNextWindowSize(ImVec2(1560.0f, 920.0f), ImGuiCond_Once);
	if (!ImGui::Begin(WindowTitle, &bWindowOpen, ImGuiWindowFlags_MenuBar))
	{
		ImGui::End();
		if (!bWindowOpen)
		{
			Close();
		}
		return;
	}

	if (ConsumeFocusRequest())
	{
		ImGui::SetWindowFocus();
	}

	ImGuiIO& IO = ImGui::GetIO();
	const bool bCtrl = IO.KeyCtrl || IO.KeySuper;
	if (ImGui::IsWindowFocused(ImGuiFocusedFlags_RootAndChildWindows))
	{
		if (bCtrl && ImGui::IsKeyPressed(ImGuiKey_S))
		{
			SaveToDisk();
		}
		else if (bCtrl && ImGui::IsKeyPressed(ImGuiKey_Z))
		{
			Undo();
		}
		else if (bCtrl && ImGui::IsKeyPressed(ImGuiKey_Y))
		{
			Redo();
		}
		else if (bCtrl && ImGui::IsKeyPressed(ImGuiKey_C))
		{
			if (const FDesignerNode* Node = FindNode(SelectedNodeId); Node && Node->Type != EWidgetType::Canvas)
			{
				ClipboardNode = *Node;
				bHasClipboardNode = true;
			}
		}
		else if (bCtrl && ImGui::IsKeyPressed(ImGuiKey_V))
		{
			if (bHasClipboardNode)
			{
				PushUndoSnapshot();
				FDesignerNode Node = ClipboardNode;
				Node.Id = NextNodeId++;
				Node.ParentId = SelectedNodeId >= 0 ? SelectedNodeId : 0;
				Node.X += 20.0f;
				Node.Y += 20.0f;
				Node.ElementId = Node.ElementId + "_copy";
				Node.Name = Node.Name + " Copy";
				DesignerNodes.push_back(Node);
				SelectedNodeId = Node.Id;
				MarkDesignerChanged();
			}
		}
		else if (!IO.WantTextInput && ImGui::IsKeyPressed(ImGuiKey_Delete))
		{
			DeleteDesignerNode(SelectedNodeId);
		}
	}

	RenderMenuBar();
	RenderToolbar();

	if (!LastError.empty())
	{
		ImGui::TextColored(ImVec4(1.0f, 0.35f, 0.35f, 1.0f), "%s", LastError.c_str());
	}
	else if (!StatusMessage.empty())
	{
		ImGui::TextDisabled("%s", StatusMessage.c_str());
	}

	if (bAnalysisDirty)
	{
		RebuildAnalysis();
	}
	EnsureDesignerModel();

	RenderDesigner();
	ImGui::End();

	if (!bWindowOpen)
	{
		Close();
	}
}

URmlUiDocumentAsset* FRmlUiEditorWidget::GetDocumentAsset() const
{
	return Cast<URmlUiDocumentAsset>(EditedObject);
}

bool FRmlUiEditorWidget::LoadFromDisk()
{
	URmlUiDocumentAsset* Asset = GetDocumentAsset();
	if (!Asset)
	{
		return false;
	}

	LastError.clear();
	StatusMessage.clear();

	URmlUiDocumentAsset* LoadedAsset = FRmlUiDocumentManager::Get().Load(Asset->GetSourcePath());
	if (LoadedAsset && LoadedAsset != Asset)
	{
		Asset = LoadedAsset;
		EditedObject = Asset;
	}

	if (Asset->GetDocumentSource().empty())
	{
		Asset->InitializeDefault();
	}

	SourceBuffer = Asset->GetDocumentSource();
	bLoaded = true;
	bAnalysisDirty = true;
	bDesignerDirty = true;
	if (Asset->GetDesignerState().empty() || !DeserializeDesignerState(Asset->GetDesignerState()))
	{
		RebuildDesignerFromSource();
	}
	else
	{
		bDesignerDirty = false;
	}
	ClearDirty();
	UndoStack.clear();
	RedoStack.clear();
	StatusMessage = "Loaded.";
	return true;
}

bool FRmlUiEditorWidget::SaveToDisk()
{
	URmlUiDocumentAsset* Asset = GetDocumentAsset();
	if (!Asset)
	{
		return false;
	}

	SyncSourceFromDesigner();
	LastError.clear();
	StatusMessage.clear();

	Asset->SetDocumentSource(SourceBuffer);
	Asset->SetDesignerState(SerializeDesignerState());
	if (!FRmlUiDocumentManager::Get().Save(Asset))
	{
		LastError = "Failed while writing RmlUi widget asset.";
		return false;
	}

	ClearDirty();
	StatusMessage = "Saved.";
	return true;
}

void FRmlUiEditorWidget::RenderMenuBar()
{
	if (!ImGui::BeginMenuBar())
	{
		return;
	}

	if (ImGui::BeginMenu("File"))
	{
		if (ImGui::MenuItem("Save", "Ctrl+S", false, IsDirty()))
		{
			SaveToDisk();
		}
		if (ImGui::MenuItem("Reload"))
		{
			LoadFromDisk();
		}
		ImGui::Separator();
		if (ImGui::MenuItem("Close"))
		{
			Close();
		}
		ImGui::EndMenu();
	}

	if (ImGui::BeginMenu("Edit"))
	{
		if (ImGui::MenuItem("Undo", "Ctrl+Z", false, !UndoStack.empty())) Undo();
		if (ImGui::MenuItem("Redo", "Ctrl+Y", false, !RedoStack.empty())) Redo();
		ImGui::Separator();
		if (ImGui::MenuItem("Duplicate", "Ctrl+D", false, SelectedNodeId > 0)) DuplicateDesignerNode(SelectedNodeId);
		if (ImGui::MenuItem("Delete", "Del", false, SelectedNodeId > 0)) DeleteDesignerNode(SelectedNodeId);
		ImGui::EndMenu();
	}

	if (ImGui::BeginMenu("Designer"))
	{
		ImGui::MenuItem("Show Grid", nullptr, &bShowGrid);
		ImGui::MenuItem("Snap To Grid", nullptr, &bSnapToGrid);
		if (ImGui::MenuItem("Import Source To Designer"))
		{
			PushUndoSnapshot();
			RebuildDesignerFromSource();
			MarkDesignerChanged();
		}
		ImGui::EndMenu();
	}

	ImGui::EndMenuBar();
}

void FRmlUiEditorWidget::RenderToolbar()
{
	if (ImGui::Button("Save"))
	{
		SaveToDisk();
	}
	ImGui::SameLine();
	if (ImGui::Button("Reload"))
	{
		LoadFromDisk();
	}
	ImGui::SameLine();
	if (ImGui::Button("Undo"))
	{
		Undo();
	}
	ImGui::SameLine();
	if (ImGui::Button("Redo"))
	{
		Redo();
	}
	ImGui::SameLine();
	if (ImGui::Button("Duplicate"))
	{
		DuplicateDesignerNode(SelectedNodeId);
	}
	ImGui::SameLine();
	if (ImGui::Button("Delete"))
	{
		DeleteDesignerNode(SelectedNodeId);
	}
	ImGui::SameLine();
	ImGui::SetNextItemWidth(90.0f);
	if (ImGui::DragFloat("Zoom", &DesignerZoom, 0.01f, 0.25f, 3.0f, "%.2f"))
	{
		DesignerZoom = ClampFloat(DesignerZoom, 0.25f, 3.0f);
	}
	ImGui::SameLine();
	ImGui::TextDisabled("%zu bytes", SourceBuffer.size());
}

void FRmlUiEditorWidget::RenderDesigner()
{
	const float LeftWidth = 260.0f;
	const float RightWidth = 360.0f;

	ImGui::BeginChild("##RmlDesignerLeft", ImVec2(LeftWidth, 0.0f), ImGuiChildFlags_Borders);
	if (ImGui::BeginTabBar("##RmlLeftTabs"))
	{
		if (ImGui::BeginTabItem("Palette"))
		{
			RenderPalette();
			ImGui::EndTabItem();
		}
		if (ImGui::BeginTabItem("Hierarchy"))
		{
			RenderHierarchy();
			ImGui::EndTabItem();
		}
		ImGui::EndTabBar();
	}
	ImGui::EndChild();

	ImGui::SameLine();
	ImGui::BeginChild("##RmlDesignerCenter", ImVec2(-RightWidth - ImGui::GetStyle().ItemSpacing.x, 0.0f), ImGuiChildFlags_Borders);
	if (ImGui::BeginTabBar("##RmlCenterTabs"))
	{
		if (ImGui::BeginTabItem("Designer"))
		{
			RenderDesignerSurface();
			ImGui::EndTabItem();
		}
		if (ImGui::BeginTabItem("Source"))
		{
			RenderSourceEditor();
			ImGui::EndTabItem();
		}
		if (ImGui::BeginTabItem("Outline"))
		{
			RenderOutline();
			ImGui::EndTabItem();
		}
		ImGui::EndTabBar();
	}
	ImGui::EndChild();

	ImGui::SameLine();
	ImGui::BeginChild("##RmlDesignerRight", ImVec2(0.0f, 0.0f), ImGuiChildFlags_Borders);
	if (ImGui::BeginTabBar("##RmlRightTabs"))
	{
		if (ImGui::BeginTabItem("Details"))
		{
			RenderDetails();
			ImGui::EndTabItem();
		}
		if (ImGui::BeginTabItem("Bindings"))
		{
			RenderBindings();
			ImGui::EndTabItem();
		}
		if (ImGui::BeginTabItem("Preview"))
		{
			RenderPreviewSettings();
			ImGui::EndTabItem();
		}
		if (ImGui::BeginTabItem("Animations"))
		{
			RenderAnimations();
			ImGui::EndTabItem();
		}
		if (ImGui::BeginTabItem("Templates"))
		{
			RenderTemplates();
			ImGui::EndTabItem();
		}
		ImGui::EndTabBar();
	}
	ImGui::EndChild();
}

void FRmlUiEditorWidget::RenderPalette()
{
	struct FPaletteEntry
	{
		EWidgetType Type;
		const char* Label;
	};

	static const FPaletteEntry Entries[] = {
		{ EWidgetType::Panel, "Panel" },
		{ EWidgetType::Text, "Text" },
		{ EWidgetType::Button, "Button" },
		{ EWidgetType::Image, "Image" },
		{ EWidgetType::ProgressBar, "Progress Bar" },
		{ EWidgetType::InputText, "Input Text" },
		{ EWidgetType::CheckBox, "Check Box" },
		{ EWidgetType::Slider, "Slider" },
		{ EWidgetType::List, "List" },
		{ EWidgetType::Custom, "Custom Tag" },
	};

	ImGui::TextDisabled("Drag to Designer or click to add.");
	ImGui::Separator();

	for (const FPaletteEntry& Entry : Entries)
	{
		const int PayloadType = static_cast<int>(Entry.Type);
		if (ImGui::Selectable(Entry.Label, false))
		{
			PushUndoSnapshot();
			AddDesignerNode(Entry.Type, SelectedNodeId >= 0 ? SelectedNodeId : 0, 64.0f, 64.0f);
			MarkDesignerChanged();
		}
		if (ImGui::BeginDragDropSource())
		{
			ImGui::SetDragDropPayload("RML_WIDGET_TYPE", &PayloadType, sizeof(PayloadType));
			ImGui::TextUnformatted(Entry.Label);
			ImGui::EndDragDropSource();
		}
	}
}

void FRmlUiEditorWidget::RenderHierarchy()
{
	if (DesignerNodes.empty())
	{
		ImGui::TextDisabled("No designer model.");
		return;
	}

	RenderHierarchyNode(0);
}

void FRmlUiEditorWidget::RenderHierarchyNode(int32 NodeId)
{
	FDesignerNode* Node = FindNode(NodeId);
	if (!Node)
	{
		return;
	}

	TArray<int32> Children;
	CollectChildren(NodeId, Children);

	ImGuiTreeNodeFlags Flags = ImGuiTreeNodeFlags_OpenOnArrow | ImGuiTreeNodeFlags_DefaultOpen;
	if (Children.empty())
	{
		Flags |= ImGuiTreeNodeFlags_Leaf;
	}
	if (SelectedNodeId == NodeId)
	{
		Flags |= ImGuiTreeNodeFlags_Selected;
	}

	const FString Label = Node->Name.empty() ? FString(TypeLabel(Node->Type)) : Node->Name;
	const bool bOpen = ImGui::TreeNodeEx(reinterpret_cast<void*>(static_cast<intptr_t>(NodeId)), Flags, "%s", Label.c_str());
	if (ImGui::IsItemClicked())
	{
		SelectedNodeId = NodeId;
	}

	if (ImGui::BeginPopupContextItem())
	{
		if (ImGui::MenuItem("Add Panel"))
		{
			PushUndoSnapshot();
			AddDesignerNode(EWidgetType::Panel, NodeId, 40.0f, 40.0f);
			MarkDesignerChanged();
		}
		if (ImGui::MenuItem("Duplicate", nullptr, false, NodeId > 0))
		{
			DuplicateDesignerNode(NodeId);
		}
		if (ImGui::MenuItem("Delete", nullptr, false, NodeId > 0))
		{
			DeleteDesignerNode(NodeId);
		}
		ImGui::EndPopup();
	}

	if (bOpen)
	{
		for (int32 ChildId : Children)
		{
			RenderHierarchyNode(ChildId);
		}
		ImGui::TreePop();
	}
}

void FRmlUiEditorWidget::RenderDesignerSurface()
{
	FDesignerNode* Canvas = FindNode(0);
	if (!Canvas)
	{
		return;
	}

	RebuildGeometryCache();

	const ImVec2 Avail = ImGui::GetContentRegionAvail();
	ImGui::BeginChild("##RmlDesignViewport", Avail, false, ImGuiWindowFlags_HorizontalScrollbar);
	const ImVec2 Origin = ImGui::GetCursorScreenPos();
	const ImVec2 CanvasSize(CanvasWidth * DesignerZoom, CanvasHeight * DesignerZoom);
	ImGui::InvisibleButton("##RmlCanvasHitTarget", CanvasSize);

	const bool bCanvasHovered = ImGui::IsItemHovered();
	ImDrawList* DrawList = ImGui::GetWindowDrawList();
	DrawList->AddRectFilled(Origin, ImVec2(Origin.x + CanvasSize.x, Origin.y + CanvasSize.y), IM_COL32(18, 19, 22, 255));
	DrawList->AddRect(Origin, ImVec2(Origin.x + CanvasSize.x, Origin.y + CanvasSize.y), IM_COL32(90, 100, 115, 255));

	if (bShowGrid)
	{
		const float GridStep = 16.0f * DesignerZoom;
		for (float X = Origin.x; X < Origin.x + CanvasSize.x; X += GridStep)
		{
			DrawList->AddLine(ImVec2(X, Origin.y), ImVec2(X, Origin.y + CanvasSize.y), IM_COL32(45, 48, 54, 120));
		}
		for (float Y = Origin.y; Y < Origin.y + CanvasSize.y; Y += GridStep)
		{
			DrawList->AddLine(ImVec2(Origin.x, Y), ImVec2(Origin.x + CanvasSize.x, Y), IM_COL32(45, 48, 54, 120));
		}
	}

	if (bCanvasHovered && ImGui::BeginDragDropTarget())
	{
		if (const ImGuiPayload* Payload = ImGui::AcceptDragDropPayload("RML_WIDGET_TYPE"))
		{
			const int TypeValue = *static_cast<const int*>(Payload->Data);
			const ImVec2 Mouse = ImGui::GetMousePos();
			const float LocalX = (Mouse.x - Origin.x) / DesignerZoom;
			const float LocalY = (Mouse.y - Origin.y) / DesignerZoom;
			int32 ParentId = HitTestDesignerNode(LocalX, LocalY);
			if (ParentId < 0)
			{
				ParentId = 0;
			}
			const FCachedGeometry* ParentGeometry = FindGeometry(ParentId);
			const FDesignerNode* ParentNode = FindNode(ParentId);
			PushUndoSnapshot();
			const float NodeX = ParentGeometry && (!ParentNode || ParentNode->SlotLayout == ESlotLayout::Canvas || ParentNode->SlotLayout == ESlotLayout::Overlay)
				? LocalX - ParentGeometry->X
				: 0.0f;
			const float NodeY = ParentGeometry && (!ParentNode || ParentNode->SlotLayout == ESlotLayout::Canvas || ParentNode->SlotLayout == ESlotLayout::Overlay)
				? LocalY - ParentGeometry->Y
				: 0.0f;
			AddDesignerNode(static_cast<EWidgetType>(TypeValue), ParentId, NodeX, NodeY);
			MarkDesignerChanged();
		}
		ImGui::EndDragDropTarget();
	}

	for (const FCachedGeometry& Geometry : CachedGeometries)
	{
		const FDesignerNode* Node = FindNode(Geometry.NodeId);
		if (!Node || Node->Type == EWidgetType::Canvas || !Node->bVisible)
		{
			continue;
		}

		const ImVec2 Min(Origin.x + Geometry.X * DesignerZoom, Origin.y + Geometry.Y * DesignerZoom);
		const ImVec2 Max(Min.x + Geometry.W * DesignerZoom, Min.y + Geometry.H * DesignerZoom);
		ImVec2 ClipMin = Origin;
		ImVec2 ClipMax(Origin.x + CanvasSize.x, Origin.y + CanvasSize.y);
		int32 ClipParentId = Geometry.ParentId;
		while (ClipParentId >= 0)
		{
			const FDesignerNode* ClipParentNode = FindNode(ClipParentId);
			const FCachedGeometry* ClipParentGeometry = FindGeometry(ClipParentId);
			if (ClipParentNode && ClipParentGeometry && ClipParentNode->bClipChildren)
			{
				ClipMin.x = (std::max)(ClipMin.x, Origin.x + ClipParentGeometry->X * DesignerZoom);
				ClipMin.y = (std::max)(ClipMin.y, Origin.y + ClipParentGeometry->Y * DesignerZoom);
				ClipMax.x = (std::min)(ClipMax.x, Origin.x + (ClipParentGeometry->X + ClipParentGeometry->W) * DesignerZoom);
				ClipMax.y = (std::min)(ClipMax.y, Origin.y + (ClipParentGeometry->Y + ClipParentGeometry->H) * DesignerZoom);
			}
			ClipParentId = ClipParentGeometry ? ClipParentGeometry->ParentId : -1;
		}
		DrawList->PushClipRect(ClipMin, ClipMax, true);
		DrawList->AddRectFilled(Min, Max, ToImColor(Node->BackgroundColor), Node->Radius * DesignerZoom);
		if (Node->BorderWidth > 0.0f)
		{
			DrawList->AddRect(Min, Max, ToImColor(Node->BorderColor), Node->Radius * DesignerZoom, 0, Node->BorderWidth * DesignerZoom);
		}

		if (Node->Type == EWidgetType::ProgressBar)
		{
			const ImVec2 FillMax(Min.x + Geometry.W * 0.65f * DesignerZoom, Max.y);
			DrawList->AddRectFilled(Min, FillMax, IM_COL32(220, 70, 70, 230), Node->Radius * DesignerZoom);
		}

		if (!Node->Text.empty())
		{
			DrawList->AddText(ImVec2(Min.x + 8.0f, Min.y + 6.0f), ToImColor(Node->TextColor), Node->Text.c_str());
		}
		else
		{
			DrawList->AddText(ImVec2(Min.x + 8.0f, Min.y + 6.0f), IM_COL32(200, 205, 215, 210), TypeLabel(Node->Type));
		}

		if (SelectedNodeId == Node->Id)
		{
			DrawList->AddRect(Min, Max, IM_COL32(80, 170, 255, 255), Node->Radius * DesignerZoom, 0, 2.0f);
			DrawList->AddRectFilled(ImVec2(Max.x - 8.0f, Max.y - 8.0f), Max, IM_COL32(80, 170, 255, 255));
			DrawList->AddText(ImVec2(Min.x, Max.y + 3.0f), IM_COL32(120, 190, 255, 230), SlotLayoutLabel(Node->SlotLayout));
		}
		DrawList->PopClipRect();
	}

	if (bCanvasHovered && ImGui::IsMouseClicked(ImGuiMouseButton_Left))
	{
		const ImVec2 Mouse = ImGui::GetMousePos();
		const float LocalX = (Mouse.x - Origin.x) / DesignerZoom;
		const float LocalY = (Mouse.y - Origin.y) / DesignerZoom;
			const int32 HitNodeId = HitTestDesignerNode(LocalX, LocalY);
			SelectedNodeId = HitNodeId >= 0 ? HitNodeId : 0;
			BuildHitTestPath(SelectedNodeId, LastHitTestPath);

			FDesignerNode* HitNode = FindNode(SelectedNodeId);
		if (HitNode && HitNode->Type != EWidgetType::Canvas && !HitNode->bLocked)
		{
			const FCachedGeometry* Geometry = FindGeometry(HitNode->Id);
			const bool bOnResize =
				Geometry &&
				LocalX >= Geometry->X + Geometry->W - 10.0f &&
				LocalY >= Geometry->Y + Geometry->H - 10.0f;
			const FDesignerNode* ParentNode = FindNode(HitNode->ParentId);
			const bool bPositionedSlot =
				!ParentNode ||
				ParentNode->SlotLayout == ESlotLayout::Canvas ||
				ParentNode->SlotLayout == ESlotLayout::Overlay;
			PushUndoSnapshot();
			DragStartMouseX = LocalX;
			DragStartMouseY = LocalY;
			DragStartNodeX = bPositionedSlot ? HitNode->X : HitNode->PaddingLeft;
			DragStartNodeY = bPositionedSlot ? HitNode->Y : HitNode->PaddingTop;
			DragStartNodeW = HitNode->W;
			DragStartNodeH = HitNode->H;
			if (bOnResize)
			{
				ResizingNodeId = HitNode->Id;
			}
			else
			{
				DraggingNodeId = HitNode->Id;
			}
		}
	}

	if (DraggingNodeId >= 0 && ImGui::IsMouseDown(ImGuiMouseButton_Left))
	{
		if (FDesignerNode* Node = FindNode(DraggingNodeId))
		{
			const ImVec2 Mouse = ImGui::GetMousePos();
			const float LocalX = (Mouse.x - Origin.x) / DesignerZoom;
			const float LocalY = (Mouse.y - Origin.y) / DesignerZoom;
			const FDesignerNode* ParentNode = FindNode(Node->ParentId);
			const bool bPositionedSlot =
				!ParentNode ||
				ParentNode->SlotLayout == ESlotLayout::Canvas ||
				ParentNode->SlotLayout == ESlotLayout::Overlay;
			float NewX = DragStartNodeX + LocalX - DragStartMouseX;
			float NewY = DragStartNodeY + LocalY - DragStartMouseY;
			if (bSnapToGrid)
			{
				NewX = std::round(NewX / 8.0f) * 8.0f;
				NewY = std::round(NewY / 8.0f) * 8.0f;
			}
			if (bPositionedSlot)
			{
				Node->X = NewX;
				Node->Y = NewY;
			}
			else
			{
				Node->PaddingLeft = (std::max)(0.0f, NewX);
				Node->PaddingTop = (std::max)(0.0f, NewY);
			}
			MarkDesignerChanged();
		}
	}
	else
	{
		DraggingNodeId = -1;
	}

	if (ResizingNodeId >= 0 && ImGui::IsMouseDown(ImGuiMouseButton_Left))
	{
		if (FDesignerNode* Node = FindNode(ResizingNodeId))
		{
			const ImVec2 Mouse = ImGui::GetMousePos();
			const float LocalX = (Mouse.x - Origin.x) / DesignerZoom;
			const float LocalY = (Mouse.y - Origin.y) / DesignerZoom;
			Node->W = (std::max)(16.0f, DragStartNodeW + LocalX - DragStartMouseX);
			Node->H = (std::max)(16.0f, DragStartNodeH + LocalY - DragStartMouseY);
			if (bSnapToGrid)
			{
				Node->W = std::round(Node->W / 8.0f) * 8.0f;
				Node->H = std::round(Node->H / 8.0f) * 8.0f;
			}
			MarkDesignerChanged();
		}
	}
	else
	{
		ResizingNodeId = -1;
	}

	ImGui::EndChild();
}

void FRmlUiEditorWidget::RenderDetails()
{
	FDesignerNode* Node = FindNode(SelectedNodeId);
	if (!Node)
	{
		ImGui::TextDisabled("No selection.");
		return;
	}

	bool bChanged = false;
	if (Node->Type == EWidgetType::Canvas)
	{
		bChanged |= ImGui::DragFloat("Canvas Width", &CanvasWidth, 1.0f, 320.0f, 7680.0f, "%.0f");
		bChanged |= ImGui::DragFloat("Canvas Height", &CanvasHeight, 1.0f, 240.0f, 4320.0f, "%.0f");
		int LayoutIndex = static_cast<int>(Node->SlotLayout);
		const char* LayoutItems[] = { "Canvas", "Overlay", "HorizontalBox", "VerticalBox", "Grid" };
		if (ImGui::Combo("Children Layout", &LayoutIndex, LayoutItems, IM_ARRAYSIZE(LayoutItems)))
		{
			Node->SlotLayout = static_cast<ESlotLayout>(LayoutIndex);
			bChanged = true;
		}
		ImGui::Checkbox("Show Grid", &bShowGrid);
		ImGui::Checkbox("Snap To Grid", &bSnapToGrid);
		if (bChanged)
		{
			MarkDesignerChanged();
		}
		return;
	}

	ImGui::Text("%s", TypeLabel(Node->Type));
	ImGui::Separator();
	if (InputFString("Name", Node->Name)) bChanged = true;
	if (InputFString("Id", Node->ElementId)) bChanged = true;
	if (InputFString("Class", Node->ClassName)) bChanged = true;
	if (Node->Type == EWidgetType::Custom && InputFString("Tag", Node->CustomTag)) bChanged = true;
	if (Node->Type == EWidgetType::Image && InputFString("Source", Node->ImageSource)) bChanged = true;
	if (Node->Type != EWidgetType::Image && InputFString("Text", Node->Text)) bChanged = true;

	ImGui::Separator();
	if (ImGui::DragFloat("X", &Node->X, 1.0f)) bChanged = true;
	if (ImGui::DragFloat("Y", &Node->Y, 1.0f)) bChanged = true;
	if (ImGui::DragFloat("Width", &Node->W, 1.0f, 1.0f, 4096.0f)) bChanged = true;
	if (ImGui::DragFloat("Height", &Node->H, 1.0f, 1.0f, 4096.0f)) bChanged = true;
	if (ImGui::DragInt("Font Size", &Node->FontSize, 1.0f, 4, 128)) bChanged = true;
	if (ImGui::DragFloat("Opacity", &Node->Opacity, 0.01f, 0.0f, 1.0f)) bChanged = true;
	if (ImGui::DragFloat("Border", &Node->BorderWidth, 0.1f, 0.0f, 24.0f)) bChanged = true;
	if (ImGui::DragFloat("Radius", &Node->Radius, 0.1f, 0.0f, 64.0f)) bChanged = true;

	ImGui::Separator();
	int LayoutIndex = static_cast<int>(Node->SlotLayout);
	const char* LayoutItems[] = { "Canvas", "Overlay", "HorizontalBox", "VerticalBox", "Grid" };
	if (ImGui::Combo("Children Layout", &LayoutIndex, LayoutItems, IM_ARRAYSIZE(LayoutItems)))
	{
		Node->SlotLayout = static_cast<ESlotLayout>(LayoutIndex);
		bChanged = true;
	}
	int SizeRuleIndex = static_cast<int>(Node->SizeRule);
	const char* SizeRuleItems[] = { "Auto", "Fill" };
	if (ImGui::Combo("Slot Size Rule", &SizeRuleIndex, SizeRuleItems, IM_ARRAYSIZE(SizeRuleItems)))
	{
		Node->SizeRule = static_cast<ESizeRule>(SizeRuleIndex);
		bChanged = true;
	}
	if (ImGui::DragFloat("Fill Weight", &Node->FillWeight, 0.05f, 0.01f, 100.0f)) bChanged = true;
	if (ImGui::DragInt("Z Order", &Node->ZOrder, 1.0f, -10000, 10000)) bChanged = true;
	if (ImGui::DragFloat4("Padding LTRB", &Node->PaddingLeft, 0.5f, 0.0f, 2048.0f)) bChanged = true;
	if (ImGui::DragFloat("Align X", &Node->AlignmentX, 0.01f, 0.0f, 1.0f)) bChanged = true;
	if (ImGui::DragFloat("Align Y", &Node->AlignmentY, 0.01f, 0.0f, 1.0f)) bChanged = true;
	if (ImGui::DragInt("Grid Row", &Node->Row, 1.0f, 0, 128)) bChanged = true;
	if (ImGui::DragInt("Grid Column", &Node->Column, 1.0f, 0, 128)) bChanged = true;
	if (ImGui::DragInt("Row Span", &Node->RowSpan, 1.0f, 1, 128)) bChanged = true;
	if (ImGui::DragInt("Column Span", &Node->ColumnSpan, 1.0f, 1, 128)) bChanged = true;

	ImGui::Separator();
	if (ColorEdit("Background", Node->BackgroundColor)) bChanged = true;
	if (ColorEdit("Text Color", Node->TextColor)) bChanged = true;
	if (ColorEdit("Border Color", Node->BorderColor)) bChanged = true;

	ImGui::Separator();
	if (ImGui::Checkbox("Visible", &Node->bVisible)) bChanged = true;
	if (ImGui::Checkbox("Locked", &Node->bLocked)) bChanged = true;
	if (ImGui::Checkbox("Clip Children", &Node->bClipChildren)) bChanged = true;

	ImGui::Separator();
	ImGui::TextDisabled("Hit Test Path");
	if (LastHitTestPath.empty())
	{
		ImGui::TextDisabled("No hit-test sample.");
	}
	else
	{
		for (size_t Index = 0; Index < LastHitTestPath.size(); ++Index)
		{
			const FDesignerNode* PathNode = FindNode(LastHitTestPath[Index]);
			if (!PathNode)
			{
				continue;
			}
			if (Index > 0)
			{
				ImGui::SameLine();
				ImGui::TextDisabled(">");
				ImGui::SameLine();
			}
			ImGui::TextUnformatted(PathNode->Name.empty() ? TypeLabel(PathNode->Type) : PathNode->Name.c_str());
		}
	}

	if (bChanged)
	{
		MarkDesignerChanged();
	}
}

void FRmlUiEditorWidget::RenderSourceEditor()
{
	if (!bLoaded)
	{
		ImGui::TextDisabled("Document is not loaded.");
		return;
	}

	if (ImGui::Button("Generate From Designer"))
	{
		SyncSourceFromDesigner();
	}
	ImGui::SameLine();
	if (ImGui::Button("Import Source To Designer"))
	{
		PushUndoSnapshot();
		RebuildDesignerFromSource();
		MarkDesignerChanged();
	}
	ImGui::Separator();

	if (SourceBuffer.capacity() < SourceBuffer.size() + 4096)
	{
		SourceBuffer.reserve(SourceBuffer.size() + 4096);
	}

	const size_t Capacity = SourceBuffer.capacity() + 1;
	SourceBuffer.resize(Capacity - 1);
	if (ImGui::InputTextMultiline(
		"##RmlUiSource",
		SourceBuffer.data(),
		Capacity,
		ImVec2(-1.0f, -1.0f),
		ImGuiInputTextFlags_AllowTabInput))
	{
		SourceBuffer.resize(std::strlen(SourceBuffer.c_str()));
		MarkDirty();
		bAnalysisDirty = true;
		StatusMessage.clear();
	}
	else
	{
		SourceBuffer.resize(std::strlen(SourceBuffer.c_str()));
	}
}

void FRmlUiEditorWidget::RenderOutline()
{
	ImGui::TextDisabled("Parsed from current RML source.");
	ImGui::Separator();

	if (Elements.empty())
	{
		ImGui::TextDisabled("No elements found.");
		return;
	}

	for (const FElementInfo& Element : Elements)
	{
		ImGui::Indent(static_cast<float>(Element.Depth) * 14.0f);
		if (Element.bClosing)
		{
			ImGui::TextDisabled("</%s>", Element.Tag.c_str());
		}
		else if (!Element.Id.empty())
		{
			ImGui::TextUnformatted((Element.Tag + "  #" + Element.Id).c_str());
		}
		else
		{
			ImGui::TextUnformatted(Element.Tag.c_str());
		}
		ImGui::Unindent(static_cast<float>(Element.Depth) * 14.0f);
	}
}

void FRmlUiEditorWidget::RenderBindings()
{
	ImGui::TextDisabled("Element IDs available for Lua SetText/SetProperty.");
	ImGui::Separator();

	if (ElementIds.empty())
	{
		ImGui::TextDisabled("No id attributes found.");
		return;
	}

	for (const FString& Id : ElementIds)
	{
		ImGui::BulletText("%s", Id.c_str());
	}
}

void FRmlUiEditorWidget::RenderPreviewSettings()
{
	ImGui::TextDisabled("Designer preview size.");
	ImGui::Separator();
	if (ImGui::Button("HD 1280x720"))
	{
		CanvasWidth = 1280.0f;
		CanvasHeight = 720.0f;
	}
	if (ImGui::Button("FHD 1920x1080"))
	{
		CanvasWidth = 1920.0f;
		CanvasHeight = 1080.0f;
	}
	if (ImGui::Button("Portrait 1080x1920"))
	{
		CanvasWidth = 1080.0f;
		CanvasHeight = 1920.0f;
	}
	ImGui::DragFloat("Width", &CanvasWidth, 1.0f, 320.0f, 7680.0f, "%.0f");
	ImGui::DragFloat("Height", &CanvasHeight, 1.0f, 240.0f, 4320.0f, "%.0f");
	ImGui::DragFloat("Zoom", &DesignerZoom, 0.01f, 0.25f, 3.0f, "%.2f");
}

void FRmlUiEditorWidget::RenderAnimations()
{
	if (ImGui::Button("Add Animation"))
	{
		PushUndoSnapshot();
		FDesignerAnimation Animation;
		Animation.Name = FString("Sequence_") + std::to_string(Animations.size() + 1);
		Animation.TargetNodeId = SelectedNodeId > 0 ? SelectedNodeId : -1;
		Animation.Duration = 1.0f;
		FDesignerTrack Track;
		Track.Id = NextTrackId++;
		Track.TargetNodeId = Animation.TargetNodeId;
		Track.Property = EAnimProperty::Opacity;
		Track.Keys.push_back({ 0.0f, 0.0f });
		Track.Keys.push_back({ Animation.Duration, 1.0f });
		Animation.Tracks.push_back(Track);
		Animations.push_back(Animation);
		SelectedAnimationIndex = static_cast<int32>(Animations.size()) - 1;
		MarkDesignerChanged();
	}

	if (Animations.empty())
	{
		ImGui::TextDisabled("No animations.");
		return;
	}

	for (size_t Index = 0; Index < Animations.size(); ++Index)
	{
		FDesignerAnimation& Animation = Animations[Index];
		ImGui::PushID(static_cast<int>(Index));
		const bool bSelected = SelectedAnimationIndex == static_cast<int32>(Index);
		ImGuiTreeNodeFlags Flags = ImGuiTreeNodeFlags_DefaultOpen | ImGuiTreeNodeFlags_OpenOnArrow;
		if (bSelected)
		{
			Flags |= ImGuiTreeNodeFlags_Selected;
		}
		if (ImGui::TreeNodeEx("Animation", Flags, "%s", Animation.Name.c_str()))
		{
			if (ImGui::IsItemClicked())
			{
				SelectedAnimationIndex = static_cast<int32>(Index);
			}
			bool bChanged = false;
			if (InputFString("Name", Animation.Name)) bChanged = true;
			if (ImGui::DragFloat("Duration", &Animation.Duration, 0.01f, 0.01f, 60.0f)) bChanged = true;
			if (ImGui::Checkbox("Loop", &Animation.bLoop)) bChanged = true;
			ImGui::DragFloat("Playhead", &TimelinePlayhead, 0.01f, 0.0f, Animation.Duration, "%.2fs");
			ImGui::DragFloat("Timeline Zoom", &TimelineZoom, 0.01f, 0.25f, 8.0f, "%.2f");
			TimelinePlayhead = ClampFloat(TimelinePlayhead, 0.0f, Animation.Duration);

			if (ImGui::Button("Add Track"))
			{
				PushUndoSnapshot();
				FDesignerTrack Track;
				Track.Id = NextTrackId++;
				Track.TargetNodeId = SelectedNodeId > 0 ? SelectedNodeId : Animation.TargetNodeId;
				Track.Property = EAnimProperty::Opacity;
				Track.Keys.push_back({ 0.0f, 0.0f });
				Track.Keys.push_back({ Animation.Duration, 1.0f });
				Animation.Tracks.push_back(Track);
				SelectedAnimationIndex = static_cast<int32>(Index);
				SelectedTrackId = Track.Id;
				SelectedKeyIndex = -1;
				MarkDesignerChanged();
			}
			ImGui::SameLine();
			if (ImGui::Button("Remove"))
			{
				PushUndoSnapshot();
				Animations.erase(Animations.begin() + static_cast<int32>(Index));
				SelectedAnimationIndex = -1;
				SelectedTrackId = -1;
				SelectedKeyIndex = -1;
				MarkDesignerChanged();
				ImGui::TreePop();
				ImGui::PopID();
				break;
			}

			ImGui::Separator();
			const float LaneHeight = 44.0f;
			const float TimelineWidth = (std::max)(260.0f, ImGui::GetContentRegionAvail().x);
			const float Duration = (std::max)(0.01f, Animation.Duration);
			ImDrawList* DrawList = ImGui::GetWindowDrawList();

			int32 TrackToRemove = -1;
			for (size_t TrackIndex = 0; TrackIndex < Animation.Tracks.size(); ++TrackIndex)
			{
				FDesignerTrack& Track = Animation.Tracks[TrackIndex];
				ImGui::PushID(Track.Id);
				ImGui::Columns(2, "##TrackColumns", false);
				ImGui::SetColumnWidth(0, 150.0f);
				if (ImGui::Selectable(AnimPropertyLabel(Track.Property), SelectedTrackId == Track.Id, 0, ImVec2(0.0f, 18.0f)))
				{
					SelectedAnimationIndex = static_cast<int32>(Index);
					SelectedTrackId = Track.Id;
					SelectedKeyIndex = -1;
				}
				int TargetNodeId = Track.TargetNodeId;
				if (ImGui::DragInt("Node", &TargetNodeId, 1.0f, -1, 100000))
				{
					Track.TargetNodeId = TargetNodeId;
					bChanged = true;
				}
				int PropertyIndex = static_cast<int>(Track.Property);
				const char* PropertyItems[] = { "Opacity", "X", "Y", "Width", "Height", "Rotation", "Scale" };
				if (ImGui::Combo("Property", &PropertyIndex, PropertyItems, IM_ARRAYSIZE(PropertyItems)))
				{
					Track.Property = static_cast<EAnimProperty>(PropertyIndex);
					bChanged = true;
				}
				if (ImGui::SmallButton("Add Key"))
				{
					PushUndoSnapshot();
					Track.Keys.push_back({ TimelinePlayhead, 0.0f });
					std::stable_sort(Track.Keys.begin(), Track.Keys.end(),
						[](const FDesignerKeyframe& A, const FDesignerKeyframe& B) { return A.Time < B.Time; });
					SelectedTrackId = Track.Id;
					SelectedKeyIndex = static_cast<int32>(Track.Keys.size()) - 1;
					MarkDesignerChanged();
				}
				ImGui::SameLine();
				if (ImGui::SmallButton("X"))
				{
					TrackToRemove = static_cast<int32>(TrackIndex);
				}

				ImGui::NextColumn();
				const ImVec2 LaneMin = ImGui::GetCursorScreenPos();
				const ImVec2 LaneSize(TimelineWidth - 170.0f, LaneHeight);
				ImGui::InvisibleButton("##Lane", LaneSize);
				const bool bLaneHovered = ImGui::IsItemHovered();
				const ImVec2 LaneMax(LaneMin.x + LaneSize.x, LaneMin.y + LaneSize.y);
				DrawList->AddRectFilled(LaneMin, LaneMax, IM_COL32(26, 28, 32, 255));
				DrawList->AddRect(LaneMin, LaneMax, IM_COL32(72, 78, 88, 255));

				const int32 TickCount = (std::max)(2, static_cast<int32>(Duration) + 1);
				for (int32 Tick = 0; Tick <= TickCount; ++Tick)
				{
					const float T = Duration * static_cast<float>(Tick) / static_cast<float>(TickCount);
					const float X = LaneMin.x + (T / Duration) * LaneSize.x;
					DrawList->AddLine(ImVec2(X, LaneMin.y), ImVec2(X, LaneMax.y), IM_COL32(70, 75, 84, 150));
					char TimeLabel[32];
					std::snprintf(TimeLabel, sizeof(TimeLabel), "%.1f", T);
					DrawList->AddText(ImVec2(X + 2.0f, LaneMin.y + 2.0f), IM_COL32(160, 166, 178, 210), TimeLabel);
				}

				const float PlayheadX = LaneMin.x + (TimelinePlayhead / Duration) * LaneSize.x;
				DrawList->AddLine(ImVec2(PlayheadX, LaneMin.y), ImVec2(PlayheadX, LaneMax.y), IM_COL32(255, 190, 70, 255), 2.0f);

				int32 ClickedKeyIndex = -1;
				float ClickedKeyDistance = 12.0f;
				for (size_t KeyIndex = 0; KeyIndex < Track.Keys.size(); ++KeyIndex)
				{
					FDesignerKeyframe& Key = Track.Keys[KeyIndex];
					Key.Time = ClampFloat(Key.Time, 0.0f, Duration);
					const float X = LaneMin.x + (Key.Time / Duration) * LaneSize.x;
					const float Y = LaneMin.y + LaneSize.y * 0.62f;
					const bool bKeySelected =
						SelectedAnimationIndex == static_cast<int32>(Index) &&
						SelectedTrackId == Track.Id &&
						SelectedKeyIndex == static_cast<int32>(KeyIndex);
					const ImU32 KeyColor = bKeySelected ? IM_COL32(80, 170, 255, 255) : IM_COL32(220, 220, 230, 255);
					DrawList->AddQuadFilled(ImVec2(X, Y - 7.0f), ImVec2(X + 7.0f, Y), ImVec2(X, Y + 7.0f), ImVec2(X - 7.0f, Y), KeyColor);
					if (bLaneHovered)
					{
						const ImVec2 Mouse = ImGui::GetMousePos();
						const float Distance = std::fabs(Mouse.x - X) + std::fabs(Mouse.y - Y);
						if (Distance < ClickedKeyDistance)
						{
							ClickedKeyDistance = Distance;
							ClickedKeyIndex = static_cast<int32>(KeyIndex);
						}
					}
				}

				if (bLaneHovered && ImGui::IsMouseClicked(ImGuiMouseButton_Left))
				{
					const ImVec2 Mouse = ImGui::GetMousePos();
					TimelinePlayhead = ClampFloat(((Mouse.x - LaneMin.x) / LaneSize.x) * Duration, 0.0f, Duration);
					SelectedAnimationIndex = static_cast<int32>(Index);
					SelectedTrackId = Track.Id;
					SelectedKeyIndex = ClickedKeyIndex;
				}
				if (bLaneHovered && ImGui::IsMouseDoubleClicked(ImGuiMouseButton_Left))
				{
					PushUndoSnapshot();
					Track.Keys.push_back({ TimelinePlayhead, 0.0f });
					std::stable_sort(Track.Keys.begin(), Track.Keys.end(),
						[](const FDesignerKeyframe& A, const FDesignerKeyframe& B) { return A.Time < B.Time; });
					SelectedKeyIndex = static_cast<int32>(Track.Keys.size()) - 1;
					MarkDesignerChanged();
				}
				if (SelectedAnimationIndex == static_cast<int32>(Index) &&
					SelectedTrackId == Track.Id &&
					SelectedKeyIndex >= 0 &&
					SelectedKeyIndex < static_cast<int32>(Track.Keys.size()) &&
					ImGui::IsMouseDown(ImGuiMouseButton_Left) &&
					bLaneHovered)
				{
					const ImVec2 Mouse = ImGui::GetMousePos();
					Track.Keys[SelectedKeyIndex].Time = ClampFloat(((Mouse.x - LaneMin.x) / LaneSize.x) * Duration, 0.0f, Duration);
					std::stable_sort(Track.Keys.begin(), Track.Keys.end(),
						[](const FDesignerKeyframe& A, const FDesignerKeyframe& B) { return A.Time < B.Time; });
					MarkDesignerChanged();
				}

				ImGui::Columns(1);
				if (SelectedAnimationIndex == static_cast<int32>(Index) &&
					SelectedTrackId == Track.Id &&
					SelectedKeyIndex >= 0 &&
					SelectedKeyIndex < static_cast<int32>(Track.Keys.size()))
				{
					FDesignerKeyframe& Key = Track.Keys[SelectedKeyIndex];
					ImGui::Indent(8.0f);
					if (ImGui::DragFloat("Key Time", &Key.Time, 0.01f, 0.0f, Duration, "%.2fs")) bChanged = true;
					if (ImGui::DragFloat("Key Value", &Key.Value, 0.01f)) bChanged = true;
					if (ImGui::SmallButton("Remove Key"))
					{
						PushUndoSnapshot();
						Track.Keys.erase(Track.Keys.begin() + SelectedKeyIndex);
						SelectedKeyIndex = -1;
						MarkDesignerChanged();
					}
					ImGui::Unindent(8.0f);
				}
				ImGui::Separator();
				ImGui::PopID();
			}

			if (TrackToRemove >= 0)
			{
				PushUndoSnapshot();
				Animation.Tracks.erase(Animation.Tracks.begin() + TrackToRemove);
				SelectedTrackId = -1;
				SelectedKeyIndex = -1;
				MarkDesignerChanged();
			}

			if (bChanged)
			{
				for (FDesignerTrack& Track : Animation.Tracks)
				{
					for (FDesignerKeyframe& Key : Track.Keys)
					{
						Key.Time = ClampFloat(Key.Time, 0.0f, Animation.Duration);
					}
					std::stable_sort(Track.Keys.begin(), Track.Keys.end(),
						[](const FDesignerKeyframe& A, const FDesignerKeyframe& B) { return A.Time < B.Time; });
				}
				MarkDesignerChanged();
			}
			ImGui::TreePop();
		}
		ImGui::PopID();
	}
}

void FRmlUiEditorWidget::RenderTemplates()
{
	if (ImGui::Button("Replace With HUD Template"))
	{
		PushUndoSnapshot();
		ClearDesignerModel();
		EnsureDesignerModel();
		AddDesignerNode(EWidgetType::Text, 0, 40.0f, 32.0f);
		if (FDesignerNode* Node = FindNode(1))
		{
			Node->Name = "Player HP Text";
			Node->ElementId = "player_hp_text";
			Node->Text = "Player HP 100 / 100";
			Node->W = 260.0f;
			Node->H = 28.0f;
		}
		AddDesignerNode(EWidgetType::ProgressBar, 0, 40.0f, 66.0f);
		if (FDesignerNode* Node = FindNode(2))
		{
			Node->Name = "Player HP Bar";
			Node->ElementId = "player_hp_fill";
			Node->W = 320.0f;
			Node->H = 18.0f;
		}
		AddDesignerNode(EWidgetType::Text, 0, 830.0f, 32.0f);
		if (FDesignerNode* Node = FindNode(3))
		{
			Node->Name = "Boss HP Text";
			Node->ElementId = "boss_hp_text";
			Node->Text = "Boss HP 500 / 500";
			Node->W = 260.0f;
			Node->H = 28.0f;
		}
		AddDesignerNode(EWidgetType::ProgressBar, 0, 830.0f, 66.0f);
		if (FDesignerNode* Node = FindNode(4))
		{
			Node->Name = "Boss HP Bar";
			Node->ElementId = "boss_hp_fill";
			Node->W = 360.0f;
			Node->H = 18.0f;
		}
		AddDesignerNode(EWidgetType::Text, 0, 40.0f, 620.0f);
		if (FDesignerNode* Node = FindNode(5))
		{
			Node->Name = "Ultimate Text";
			Node->ElementId = "ultimate_text";
			Node->Text = "Ultimate 0%";
		}
		AddDesignerNode(EWidgetType::Text, 0, 40.0f, 654.0f);
		if (FDesignerNode* Node = FindNode(6))
		{
			Node->Name = "Combo Text";
			Node->ElementId = "combo_text";
			Node->Text = "Combo 0";
		}
		MarkDesignerChanged();
	}

	ImGui::Separator();
	ImGui::TextUnformatted("Lua:");
	ImGui::TextUnformatted("local w = UI.CreateWidget(\"Content/UI/BossHUD.uasset\")");
	ImGui::TextUnformatted("w:AddToViewport()");
	ImGui::TextUnformatted("w:set_text(\"player_hp_text\", \"100 / 100\")");
	ImGui::TextUnformatted("w:set_property(\"boss_hp_fill\", \"width\", \"75%\")");
}

void FRmlUiEditorWidget::RebuildAnalysis()
{
	AnalyseRmlSource(SourceBuffer, Elements, ElementIds);
	bAnalysisDirty = false;
}

void FRmlUiEditorWidget::RebuildDesignerFromSource()
{
	ClearDesignerModel();
	EnsureDesignerModel();

	int32 Stagger = 0;
	TArray<int32> ParentStack;
	ParentStack.push_back(0);

	size_t Pos = 0;
	while ((Pos = SourceBuffer.find('<', Pos)) != std::string::npos)
	{
		if (Pos + 1 >= SourceBuffer.size())
		{
			break;
		}
		const char Next = SourceBuffer[Pos + 1];
		if (Next == '!' || Next == '?')
		{
			const size_t End = SourceBuffer.find('>', Pos + 1);
			Pos = End == std::string::npos ? SourceBuffer.size() : End + 1;
			continue;
		}

		const bool bClosing = Next == '/';
		size_t NamePos = Pos + (bClosing ? 2 : 1);
		while (NamePos < SourceBuffer.size() && std::isspace(static_cast<unsigned char>(SourceBuffer[NamePos])))
		{
			++NamePos;
		}
		const size_t NameBegin = NamePos;
		while (NamePos < SourceBuffer.size() && IsNameChar(SourceBuffer[NamePos]))
		{
			++NamePos;
		}
		if (NamePos == NameBegin)
		{
			++Pos;
			continue;
		}

		const FString Tag = SourceBuffer.substr(NameBegin, NamePos - NameBegin);
		const size_t End = SourceBuffer.find('>', NamePos);
		if (End == std::string::npos)
		{
			break;
		}

		if (bClosing)
		{
			if (!ParentStack.empty() && Tag != "rml" && Tag != "head" && Tag != "style" && Tag != "body")
			{
				ParentStack.pop_back();
			}
			Pos = End + 1;
			continue;
		}

		const bool bSelfClosing = End > Pos && SourceBuffer[End - 1] == '/';
		const std::string TagText = SourceBuffer.substr(NamePos, End - NamePos);
		if (Tag == "rml" || Tag == "head" || Tag == "style" || Tag == "body" || Tag == "title")
		{
			Pos = End + 1;
			continue;
		}

		const FString Id = GetAttributeValue(TagText, "id");
		const FString ClassName = GetAttributeValue(TagText, "class");
		const FString Style = GetAttributeValue(TagText, "style");
		const int32 ParentId = ParentStack.empty() ? 0 : ParentStack.back();
		const int32 NodeId = AddDesignerNode(TypeFromTag(Tag, ClassName), ParentId, 32.0f + Stagger * 18.0f, 32.0f + Stagger * 18.0f);
		if (FDesignerNode* Node = FindNode(NodeId))
		{
			Node->ElementId = Id.empty() ? Node->ElementId : Id;
			Node->ClassName = ClassName;
			Node->CustomTag = Tag;
			Node->X = ExtractCssPx(Style, "left", Node->X);
			Node->Y = ExtractCssPx(Style, "top", Node->Y);
			Node->W = ExtractCssPx(Style, "width", Node->W);
			Node->H = ExtractCssPx(Style, "height", Node->H);
			Node->FontSize = static_cast<int32>(ExtractCssPx(Style, "font-size", static_cast<float>(Node->FontSize)));
			const size_t TextBegin = End + 1;
			const size_t TextEnd = SourceBuffer.find('<', TextBegin);
			if (TextEnd != FString::npos && TextEnd > TextBegin)
			{
				Node->Text = SourceBuffer.substr(TextBegin, TextEnd - TextBegin);
				if (Node->Type == EWidgetType::Panel && !Node->Text.empty())
				{
					Node->Type = EWidgetType::Text;
				}
			}
		}

		++Stagger;
		if (!bSelfClosing)
		{
			ParentStack.push_back(NodeId);
		}
		Pos = End + 1;
	}

	if (DesignerNodes.size() == 1)
	{
		AddDesignerNode(EWidgetType::Panel, 0, 48.0f, 48.0f);
	}

	SelectedNodeId = 0;
	bDesignerDirty = false;
	SyncSourceFromDesigner();
}

void FRmlUiEditorWidget::SyncSourceFromDesigner()
{
	if (bSyncingSourceFromDesigner)
	{
		return;
	}

	bSyncingSourceFromDesigner = true;
	SourceBuffer = GenerateRmlDocument();
	bSyncingSourceFromDesigner = false;
	bAnalysisDirty = true;
}

FString FRmlUiEditorWidget::SerializeDesignerState() const
{
	std::ostringstream Out;
	Out << "RMLUI_DESIGNER_STATE\t1\n";
	Out << "CANVAS\t" << CanvasWidth << "\t" << CanvasHeight << "\t" << NextNodeId << "\t" << NextTrackId << "\n";

	for (const FDesignerNode& Node : DesignerNodes)
	{
		Out << "NODE"
			<< "\t" << Node.Id
			<< "\t" << Node.ParentId
			<< "\t" << static_cast<int32>(Node.Type)
			<< "\t" << EscapeStateString(Node.Name)
			<< "\t" << EscapeStateString(Node.ElementId)
			<< "\t" << EscapeStateString(Node.ClassName)
			<< "\t" << EscapeStateString(Node.Text)
			<< "\t" << EscapeStateString(Node.ImageSource)
			<< "\t" << EscapeStateString(Node.CustomTag)
			<< "\t" << Node.X
			<< "\t" << Node.Y
			<< "\t" << Node.W
			<< "\t" << Node.H
			<< "\t" << Node.BorderWidth
			<< "\t" << Node.Radius
			<< "\t" << Node.FontSize
			<< "\t" << Node.Opacity
			<< "\t" << (Node.bVisible ? 1 : 0)
			<< "\t" << (Node.bLocked ? 1 : 0)
			<< "\t" << (Node.bClipChildren ? 1 : 0)
			<< "\t" << static_cast<int32>(Node.SlotLayout)
			<< "\t" << static_cast<int32>(Node.SizeRule)
			<< "\t" << Node.PaddingLeft
			<< "\t" << Node.PaddingTop
			<< "\t" << Node.PaddingRight
			<< "\t" << Node.PaddingBottom
			<< "\t" << Node.AlignmentX
			<< "\t" << Node.AlignmentY
			<< "\t" << Node.FillWeight
			<< "\t" << Node.Row
			<< "\t" << Node.Column
			<< "\t" << Node.RowSpan
			<< "\t" << Node.ColumnSpan
			<< "\t" << Node.ZOrder
			<< "\t" << Node.BackgroundColor.R
			<< "\t" << Node.BackgroundColor.G
			<< "\t" << Node.BackgroundColor.B
			<< "\t" << Node.BackgroundColor.A
			<< "\t" << Node.TextColor.R
			<< "\t" << Node.TextColor.G
			<< "\t" << Node.TextColor.B
			<< "\t" << Node.TextColor.A
			<< "\t" << Node.BorderColor.R
			<< "\t" << Node.BorderColor.G
			<< "\t" << Node.BorderColor.B
			<< "\t" << Node.BorderColor.A
			<< "\n";
	}

	for (size_t AnimationIndex = 0; AnimationIndex < Animations.size(); ++AnimationIndex)
	{
		const FDesignerAnimation& Animation = Animations[AnimationIndex];
		Out << "ANIM"
			<< "\t" << AnimationIndex
			<< "\t" << EscapeStateString(Animation.Name)
			<< "\t" << Animation.TargetNodeId
			<< "\t" << EscapeStateString(Animation.Property)
			<< "\t" << Animation.FromValue
			<< "\t" << Animation.ToValue
			<< "\t" << Animation.Duration
			<< "\t" << (Animation.bLoop ? 1 : 0)
			<< "\n";

		for (const FDesignerTrack& Track : Animation.Tracks)
		{
			Out << "TRACK"
				<< "\t" << AnimationIndex
				<< "\t" << Track.Id
				<< "\t" << Track.TargetNodeId
				<< "\t" << static_cast<int32>(Track.Property)
				<< "\t" << (Track.bExpanded ? 1 : 0)
				<< "\n";
			for (const FDesignerKeyframe& Key : Track.Keys)
			{
				Out << "KEY"
					<< "\t" << AnimationIndex
					<< "\t" << Track.Id
					<< "\t" << Key.Time
					<< "\t" << Key.Value
					<< "\n";
			}
		}
	}

	return Out.str();
}

bool FRmlUiEditorWidget::DeserializeDesignerState(const FString& State)
{
	std::istringstream In(State);
	FString Line;
	if (!std::getline(In, Line))
	{
		return false;
	}

	TArray<FString> Header = SplitStateFields(Line);
	if (Header.size() < 2 || Header[0] != "RMLUI_DESIGNER_STATE" || StateInt(Header, 1) != 1)
	{
		return false;
	}

	TArray<FDesignerNode> LoadedNodes;
	TArray<FDesignerAnimation> LoadedAnimations;
	int32 LoadedNextNodeId = 1;
	int32 LoadedNextTrackId = 1;
	float LoadedCanvasWidth = CanvasWidth;
	float LoadedCanvasHeight = CanvasHeight;

	while (std::getline(In, Line))
	{
		if (!Line.empty() && Line.back() == '\r')
		{
			Line.pop_back();
		}
		if (Line.empty())
		{
			continue;
		}

		TArray<FString> Fields = SplitStateFields(Line);
		if (Fields.empty())
		{
			continue;
		}

		if (Fields[0] == "CANVAS")
		{
			LoadedCanvasWidth = StateFloat(Fields, 1, LoadedCanvasWidth);
			LoadedCanvasHeight = StateFloat(Fields, 2, LoadedCanvasHeight);
			LoadedNextNodeId = StateInt(Fields, 3, LoadedNextNodeId);
			LoadedNextTrackId = StateInt(Fields, 4, LoadedNextTrackId);
			continue;
		}

		if (Fields[0] == "NODE")
		{
			FDesignerNode Node;
			Node.Id = StateInt(Fields, 1);
			Node.ParentId = StateInt(Fields, 2, -1);
			Node.Type = static_cast<EWidgetType>(StateInt(Fields, 3, static_cast<int32>(EWidgetType::Panel)));
			Node.Name = StateString(Fields, 4);
			Node.ElementId = StateString(Fields, 5);
			Node.ClassName = StateString(Fields, 6);
			Node.Text = StateString(Fields, 7);
			Node.ImageSource = StateString(Fields, 8);
			Node.CustomTag = StateString(Fields, 9);
			Node.X = StateFloat(Fields, 10);
			Node.Y = StateFloat(Fields, 11);
			Node.W = StateFloat(Fields, 12, 160.0f);
			Node.H = StateFloat(Fields, 13, 48.0f);
			Node.BorderWidth = StateFloat(Fields, 14);
			Node.Radius = StateFloat(Fields, 15);
			Node.FontSize = StateInt(Fields, 16, 18);
			Node.Opacity = StateFloat(Fields, 17, 1.0f);
			Node.bVisible = StateInt(Fields, 18, 1) != 0;
			Node.bLocked = StateInt(Fields, 19) != 0;
			Node.bClipChildren = StateInt(Fields, 20) != 0;
			Node.SlotLayout = static_cast<ESlotLayout>(StateInt(Fields, 21, static_cast<int32>(ESlotLayout::Canvas)));
			Node.SizeRule = static_cast<ESizeRule>(StateInt(Fields, 22, static_cast<int32>(ESizeRule::Auto)));
			Node.PaddingLeft = StateFloat(Fields, 23);
			Node.PaddingTop = StateFloat(Fields, 24);
			Node.PaddingRight = StateFloat(Fields, 25);
			Node.PaddingBottom = StateFloat(Fields, 26);
			Node.AlignmentX = StateFloat(Fields, 27);
			Node.AlignmentY = StateFloat(Fields, 28);
			Node.FillWeight = StateFloat(Fields, 29, 1.0f);
			Node.Row = StateInt(Fields, 30);
			Node.Column = StateInt(Fields, 31);
			Node.RowSpan = StateInt(Fields, 32, 1);
			Node.ColumnSpan = StateInt(Fields, 33, 1);
			Node.ZOrder = StateInt(Fields, 34);
			Node.BackgroundColor = { StateFloat(Fields, 35, 0.08f), StateFloat(Fields, 36, 0.08f), StateFloat(Fields, 37, 0.09f), StateFloat(Fields, 38, 0.78f) };
			Node.TextColor = { StateFloat(Fields, 39, 1.0f), StateFloat(Fields, 40, 1.0f), StateFloat(Fields, 41, 1.0f), StateFloat(Fields, 42, 1.0f) };
			Node.BorderColor = { StateFloat(Fields, 43, 1.0f), StateFloat(Fields, 44, 1.0f), StateFloat(Fields, 45, 1.0f), StateFloat(Fields, 46, 0.35f) };
			LoadedNodes.push_back(Node);
			LoadedNextNodeId = (std::max)(LoadedNextNodeId, Node.Id + 1);
			continue;
		}

		if (Fields[0] == "ANIM")
		{
			const int32 AnimationIndex = StateInt(Fields, 1, static_cast<int32>(LoadedAnimations.size()));
			if (AnimationIndex < 0)
			{
				continue;
			}
			if (LoadedAnimations.size() <= static_cast<size_t>(AnimationIndex))
			{
				LoadedAnimations.resize(static_cast<size_t>(AnimationIndex) + 1);
			}
			FDesignerAnimation& Animation = LoadedAnimations[AnimationIndex];
			Animation.Name = StateString(Fields, 2);
			Animation.TargetNodeId = StateInt(Fields, 3, -1);
			Animation.Property = StateString(Fields, 4);
			Animation.FromValue = StateFloat(Fields, 5);
			Animation.ToValue = StateFloat(Fields, 6, 1.0f);
			Animation.Duration = StateFloat(Fields, 7, 0.25f);
			Animation.bLoop = StateInt(Fields, 8) != 0;
			continue;
		}

		if (Fields[0] == "TRACK")
		{
			const int32 AnimationIndex = StateInt(Fields, 1, -1);
			if (AnimationIndex < 0)
			{
				continue;
			}
			if (LoadedAnimations.size() <= static_cast<size_t>(AnimationIndex))
			{
				LoadedAnimations.resize(static_cast<size_t>(AnimationIndex) + 1);
			}
			FDesignerTrack Track;
			Track.Id = StateInt(Fields, 2, LoadedNextTrackId++);
			Track.TargetNodeId = StateInt(Fields, 3, -1);
			Track.Property = static_cast<EAnimProperty>(StateInt(Fields, 4, static_cast<int32>(EAnimProperty::Opacity)));
			Track.bExpanded = StateInt(Fields, 5, 1) != 0;
			LoadedAnimations[AnimationIndex].Tracks.push_back(Track);
			LoadedNextTrackId = (std::max)(LoadedNextTrackId, Track.Id + 1);
			continue;
		}

		if (Fields[0] == "KEY")
		{
			const int32 AnimationIndex = StateInt(Fields, 1, -1);
			const int32 TrackId = StateInt(Fields, 2, -1);
			if (AnimationIndex < 0 || TrackId < 0 || LoadedAnimations.size() <= static_cast<size_t>(AnimationIndex))
			{
				continue;
			}
			for (FDesignerTrack& Track : LoadedAnimations[AnimationIndex].Tracks)
			{
				if (Track.Id == TrackId)
				{
					Track.Keys.push_back({ StateFloat(Fields, 3), StateFloat(Fields, 4) });
					break;
				}
			}
		}
	}

	if (LoadedNodes.empty())
	{
		return false;
	}

	DesignerNodes = std::move(LoadedNodes);
	Animations = std::move(LoadedAnimations);
	CanvasWidth = LoadedCanvasWidth;
	CanvasHeight = LoadedCanvasHeight;
	NextNodeId = LoadedNextNodeId;
	NextTrackId = LoadedNextTrackId;
	SelectedNodeId = 0;
	SelectedAnimationIndex = -1;
	SelectedTrackId = -1;
	SelectedKeyIndex = -1;
	DraggingNodeId = -1;
	ResizingNodeId = -1;
	CachedGeometries.clear();
	for (FDesignerAnimation& Animation : Animations)
	{
		for (FDesignerTrack& Track : Animation.Tracks)
		{
			std::stable_sort(Track.Keys.begin(), Track.Keys.end(),
				[](const FDesignerKeyframe& A, const FDesignerKeyframe& B) { return A.Time < B.Time; });
		}
	}
	return true;
}

void FRmlUiEditorWidget::InsertTemplate(const char* Text)
{
	if (!Text)
	{
		return;
	}

	PushUndoSnapshot();
	SourceBuffer = Text;
	RebuildDesignerFromSource();
	MarkDesignerChanged();
}

void FRmlUiEditorWidget::PushUndoSnapshot()
{
	FDesignerSnapshot Snapshot;
	Snapshot.Nodes = DesignerNodes;
	Snapshot.Animations = Animations;
	Snapshot.SelectedNodeId = SelectedNodeId;
	Snapshot.NextNodeId = NextNodeId;
	Snapshot.NextTrackId = NextTrackId;
	UndoStack.push_back(Snapshot);
	RedoStack.clear();
	if (UndoStack.size() > 100)
	{
		UndoStack.erase(UndoStack.begin());
	}
}

void FRmlUiEditorWidget::RestoreSnapshot(const FDesignerSnapshot& Snapshot)
{
	DesignerNodes = Snapshot.Nodes;
	Animations = Snapshot.Animations;
	SelectedNodeId = Snapshot.SelectedNodeId;
	NextNodeId = Snapshot.NextNodeId;
	NextTrackId = Snapshot.NextTrackId;
	MarkDesignerChanged();
}

void FRmlUiEditorWidget::Undo()
{
	if (UndoStack.empty())
	{
		return;
	}

	FDesignerSnapshot RedoSnapshot;
	RedoSnapshot.Nodes = DesignerNodes;
	RedoSnapshot.Animations = Animations;
	RedoSnapshot.SelectedNodeId = SelectedNodeId;
	RedoSnapshot.NextNodeId = NextNodeId;
	RedoSnapshot.NextTrackId = NextTrackId;
	RedoStack.push_back(RedoSnapshot);

	const FDesignerSnapshot Snapshot = UndoStack.back();
	UndoStack.pop_back();
	RestoreSnapshot(Snapshot);
}

void FRmlUiEditorWidget::Redo()
{
	if (RedoStack.empty())
	{
		return;
	}

	FDesignerSnapshot UndoSnapshot;
	UndoSnapshot.Nodes = DesignerNodes;
	UndoSnapshot.Animations = Animations;
	UndoSnapshot.SelectedNodeId = SelectedNodeId;
	UndoSnapshot.NextNodeId = NextNodeId;
	UndoSnapshot.NextTrackId = NextTrackId;
	UndoStack.push_back(UndoSnapshot);

	const FDesignerSnapshot Snapshot = RedoStack.back();
	RedoStack.pop_back();
	RestoreSnapshot(Snapshot);
}

void FRmlUiEditorWidget::MarkDesignerChanged()
{
	bDesignerDirty = true;
	SyncSourceFromDesigner();
	MarkDirty();
	StatusMessage.clear();
}

void FRmlUiEditorWidget::EnsureDesignerModel()
{
	if (!DesignerNodes.empty())
	{
		return;
	}

	FDesignerNode Canvas;
	Canvas.Id = 0;
	Canvas.ParentId = -1;
	Canvas.Type = EWidgetType::Canvas;
	Canvas.Name = "Canvas";
	Canvas.ElementId = "root";
	Canvas.W = CanvasWidth;
	Canvas.H = CanvasHeight;
	Canvas.SlotLayout = ESlotLayout::Canvas;
	Canvas.BackgroundColor = { 0.02f, 0.02f, 0.025f, 1.0f };
	DesignerNodes.push_back(Canvas);
	NextNodeId = 1;
}

void FRmlUiEditorWidget::ClearDesignerModel()
{
	DesignerNodes.clear();
	Animations.clear();
	CachedGeometries.clear();
	SelectedNodeId = 0;
	SelectedAnimationIndex = -1;
	SelectedTrackId = -1;
	SelectedKeyIndex = -1;
	NextNodeId = 1;
	NextTrackId = 1;
	DraggingNodeId = -1;
	ResizingNodeId = -1;
	bHasClipboardNode = false;
	LastHitTestPath.clear();
}

FDesignerNode* FRmlUiEditorWidget::FindNode(int32 NodeId)
{
	for (FDesignerNode& Node : DesignerNodes)
	{
		if (Node.Id == NodeId)
		{
			return &Node;
		}
	}
	return nullptr;
}

const FDesignerNode* FRmlUiEditorWidget::FindNode(int32 NodeId) const
{
	for (const FDesignerNode& Node : DesignerNodes)
	{
		if (Node.Id == NodeId)
		{
			return &Node;
		}
	}
	return nullptr;
}

int32 FRmlUiEditorWidget::AddDesignerNode(EWidgetType Type, int32 ParentId, float X, float Y)
{
	EnsureDesignerModel();
	if (!FindNode(ParentId))
	{
		ParentId = 0;
	}

	FDesignerNode Node;
	Node.Id = NextNodeId++;
	Node.ParentId = ParentId;
	Node.Type = Type;
	Node.Name = FString(TypeLabel(Type)) + " " + std::to_string(Node.Id);
	Node.ElementId = FString("widget_") + std::to_string(Node.Id);
	Node.ClassName = TypeLabel(Type);
	Node.CustomTag = DefaultTagForType(Type);
	Node.X = X;
	Node.Y = Y;

	switch (Type)
	{
	case EWidgetType::Text:
		Node.W = 220.0f;
		Node.H = 32.0f;
		Node.Text = "Text";
		Node.BackgroundColor = { 0.0f, 0.0f, 0.0f, 0.0f };
		break;
	case EWidgetType::Button:
		Node.W = 160.0f;
		Node.H = 42.0f;
		Node.Text = "Button";
		Node.BackgroundColor = { 0.12f, 0.24f, 0.38f, 0.95f };
		Node.Radius = 4.0f;
		break;
	case EWidgetType::Image:
		Node.W = 128.0f;
		Node.H = 128.0f;
		Node.ImageSource = "Content/Texture/T_Lightning.png";
		Node.BackgroundColor = { 0.18f, 0.18f, 0.22f, 1.0f };
		break;
	case EWidgetType::ProgressBar:
		Node.W = 320.0f;
		Node.H = 22.0f;
		Node.Text = "";
		Node.BackgroundColor = { 0.0f, 0.0f, 0.0f, 0.62f };
		break;
	case EWidgetType::InputText:
		Node.W = 220.0f;
		Node.H = 36.0f;
		Node.Text = "Input";
		Node.BackgroundColor = { 0.08f, 0.08f, 0.09f, 0.95f };
		break;
	case EWidgetType::CheckBox:
		Node.W = 24.0f;
		Node.H = 24.0f;
		Node.ClassName = "checkbox";
		break;
	case EWidgetType::Slider:
		Node.W = 220.0f;
		Node.H = 24.0f;
		break;
	case EWidgetType::List:
		Node.W = 260.0f;
		Node.H = 160.0f;
		Node.Text = "Item 1\nItem 2\nItem 3";
		break;
	default:
		break;
	}

	DesignerNodes.push_back(Node);
	SelectedNodeId = Node.Id;
	return Node.Id;
}

void FRmlUiEditorWidget::DeleteDesignerNode(int32 NodeId)
{
	if (NodeId <= 0 || !FindNode(NodeId))
	{
		return;
	}

	PushUndoSnapshot();
	DesignerNodes.erase(std::remove_if(DesignerNodes.begin(), DesignerNodes.end(),
		[&](const FDesignerNode& Node)
		{
			return Node.Id == NodeId || IsDescendantOf(Node.Id, NodeId);
		}), DesignerNodes.end());

	SelectedNodeId = 0;
	MarkDesignerChanged();
}

void FRmlUiEditorWidget::DuplicateDesignerNode(int32 NodeId)
{
	const FDesignerNode* Source = FindNode(NodeId);
	if (!Source || Source->Type == EWidgetType::Canvas)
	{
		return;
	}

	PushUndoSnapshot();
	FDesignerNode Copy = *Source;
	Copy.Id = NextNodeId++;
	Copy.Name += " Copy";
	Copy.ElementId += "_copy";
	Copy.X += 24.0f;
	Copy.Y += 24.0f;
	DesignerNodes.push_back(Copy);
	SelectedNodeId = Copy.Id;
	MarkDesignerChanged();
}

bool FRmlUiEditorWidget::IsDescendantOf(int32 NodeId, int32 PossibleParentId) const
{
	const FDesignerNode* Node = FindNode(NodeId);
	while (Node && Node->ParentId >= 0)
	{
		if (Node->ParentId == PossibleParentId)
		{
			return true;
		}
		Node = FindNode(Node->ParentId);
	}
	return false;
}

void FRmlUiEditorWidget::CollectChildren(int32 ParentId, TArray<int32>& OutChildren) const
{
	OutChildren.clear();
	for (const FDesignerNode& Node : DesignerNodes)
	{
		if (Node.ParentId == ParentId)
		{
			OutChildren.push_back(Node.Id);
		}
	}
}

void FRmlUiEditorWidget::BuildHitTestPath(int32 NodeId, TArray<int32>& OutPath) const
{
	OutPath.clear();
	const FDesignerNode* Node = FindNode(NodeId);
	while (Node)
	{
		OutPath.push_back(Node->Id);
		if (Node->ParentId < 0)
		{
			break;
		}
		Node = FindNode(Node->ParentId);
	}
	std::reverse(OutPath.begin(), OutPath.end());
}

FRmlUiEditorWidget::FCachedGeometry* FRmlUiEditorWidget::FindGeometry(int32 NodeId)
{
	for (FCachedGeometry& Geometry : CachedGeometries)
	{
		if (Geometry.NodeId == NodeId)
		{
			return &Geometry;
		}
	}
	return nullptr;
}

const FRmlUiEditorWidget::FCachedGeometry* FRmlUiEditorWidget::FindGeometry(int32 NodeId) const
{
	for (const FCachedGeometry& Geometry : CachedGeometries)
	{
		if (Geometry.NodeId == NodeId)
		{
			return &Geometry;
		}
	}
	return nullptr;
}

void FRmlUiEditorWidget::RebuildGeometryCache()
{
	CachedGeometries.clear();

	FDesignerNode* Canvas = FindNode(0);
	if (!Canvas)
	{
		return;
	}

	Canvas->W = CanvasWidth;
	Canvas->H = CanvasHeight;

	FCachedGeometry Root;
	Root.NodeId = Canvas->Id;
	Root.ParentId = Canvas->ParentId;
	Root.X = 0.0f;
	Root.Y = 0.0f;
	Root.W = CanvasWidth;
	Root.H = CanvasHeight;
	Root.ZOrder = Canvas->ZOrder;
	Root.Layer = 0;
	CachedGeometries.push_back(Root);
	BuildChildGeometries(Canvas->Id, Root, 1);

	if (CachedGeometries.size() > 2)
	{
		std::stable_sort(CachedGeometries.begin() + 1, CachedGeometries.end(),
			[](const FCachedGeometry& A, const FCachedGeometry& B)
			{
				if (A.Layer != B.Layer)
				{
					return A.Layer < B.Layer;
				}
				if (A.ZOrder != B.ZOrder)
				{
					return A.ZOrder < B.ZOrder;
				}
				return A.NodeId < B.NodeId;
			});
	}
}

void FRmlUiEditorWidget::BuildChildGeometries(int32 ParentId, const FCachedGeometry& ParentGeometry, int32 Layer)
{
	const FDesignerNode* ParentNode = FindNode(ParentId);
	if (!ParentNode)
	{
		return;
	}

	TArray<int32> Children;
	CollectChildren(ParentId, Children);
	std::stable_sort(Children.begin(), Children.end(),
		[&](int32 A, int32 B)
		{
			const FDesignerNode* NodeA = FindNode(A);
			const FDesignerNode* NodeB = FindNode(B);
			const int32 ZA = NodeA ? NodeA->ZOrder : 0;
			const int32 ZB = NodeB ? NodeB->ZOrder : 0;
			return ZA == ZB ? A < B : ZA < ZB;
		});

	if (Children.empty())
	{
		return;
	}

	const auto PushChild = [&](const FDesignerNode& Child, float X, float Y, float W, float H)
	{
		FCachedGeometry Geometry;
		Geometry.NodeId = Child.Id;
		Geometry.ParentId = Child.ParentId;
		Geometry.X = X;
		Geometry.Y = Y;
		Geometry.W = (std::max)(1.0f, W);
		Geometry.H = (std::max)(1.0f, H);
		Geometry.ZOrder = Child.ZOrder;
		Geometry.Layer = Layer;
		Geometry.bClipped = ParentGeometry.bClipped;
		CachedGeometries.push_back(Geometry);
		BuildChildGeometries(Child.Id, Geometry, Layer + 1);
	};

	if (ParentNode->SlotLayout == ESlotLayout::HorizontalBox)
	{
		float FixedWidth = 0.0f;
		float TotalFill = 0.0f;
		for (int32 ChildId : Children)
		{
			const FDesignerNode* Child = FindNode(ChildId);
			if (!Child || !Child->bVisible)
			{
				continue;
			}
			const float OuterWidth = Child->W + Child->PaddingLeft + Child->PaddingRight;
			if (Child->SizeRule == ESizeRule::Fill)
			{
				TotalFill += (std::max)(0.01f, Child->FillWeight);
			}
			else
			{
				FixedWidth += OuterWidth;
			}
		}

		const float RemainingWidth = (std::max)(0.0f, ParentGeometry.W - FixedWidth);
		float CursorX = ParentGeometry.X;
		for (int32 ChildId : Children)
		{
			const FDesignerNode* Child = FindNode(ChildId);
			if (!Child || !Child->bVisible)
			{
				continue;
			}
			const float OuterWidth = Child->SizeRule == ESizeRule::Fill && TotalFill > 0.0f
				? RemainingWidth * ((std::max)(0.01f, Child->FillWeight) / TotalFill)
				: Child->W + Child->PaddingLeft + Child->PaddingRight;
			const float AvailableW = (std::max)(1.0f, OuterWidth - Child->PaddingLeft - Child->PaddingRight);
			const float AvailableH = (std::max)(1.0f, ParentGeometry.H - Child->PaddingTop - Child->PaddingBottom);
			const float W = Child->SizeRule == ESizeRule::Fill ? AvailableW : (std::min)(Child->W, AvailableW);
			const float H = (std::min)(Child->H, AvailableH);
			const float X = CursorX + Child->PaddingLeft;
			const float Y = ParentGeometry.Y + Child->PaddingTop + (AvailableH - H) * ClampFloat(Child->AlignmentY, 0.0f, 1.0f);
			PushChild(*Child, X, Y, W, H);
			CursorX += OuterWidth;
		}
		return;
	}

	if (ParentNode->SlotLayout == ESlotLayout::VerticalBox)
	{
		float FixedHeight = 0.0f;
		float TotalFill = 0.0f;
		for (int32 ChildId : Children)
		{
			const FDesignerNode* Child = FindNode(ChildId);
			if (!Child || !Child->bVisible)
			{
				continue;
			}
			const float OuterHeight = Child->H + Child->PaddingTop + Child->PaddingBottom;
			if (Child->SizeRule == ESizeRule::Fill)
			{
				TotalFill += (std::max)(0.01f, Child->FillWeight);
			}
			else
			{
				FixedHeight += OuterHeight;
			}
		}

		const float RemainingHeight = (std::max)(0.0f, ParentGeometry.H - FixedHeight);
		float CursorY = ParentGeometry.Y;
		for (int32 ChildId : Children)
		{
			const FDesignerNode* Child = FindNode(ChildId);
			if (!Child || !Child->bVisible)
			{
				continue;
			}
			const float OuterHeight = Child->SizeRule == ESizeRule::Fill && TotalFill > 0.0f
				? RemainingHeight * ((std::max)(0.01f, Child->FillWeight) / TotalFill)
				: Child->H + Child->PaddingTop + Child->PaddingBottom;
			const float AvailableW = (std::max)(1.0f, ParentGeometry.W - Child->PaddingLeft - Child->PaddingRight);
			const float AvailableH = (std::max)(1.0f, OuterHeight - Child->PaddingTop - Child->PaddingBottom);
			const float W = (std::min)(Child->W, AvailableW);
			const float H = Child->SizeRule == ESizeRule::Fill ? AvailableH : (std::min)(Child->H, AvailableH);
			const float X = ParentGeometry.X + Child->PaddingLeft + (AvailableW - W) * ClampFloat(Child->AlignmentX, 0.0f, 1.0f);
			const float Y = CursorY + Child->PaddingTop;
			PushChild(*Child, X, Y, W, H);
			CursorY += OuterHeight;
		}
		return;
	}

	if (ParentNode->SlotLayout == ESlotLayout::Grid)
	{
		int32 MaxRow = 1;
		int32 MaxColumn = 1;
		for (int32 ChildId : Children)
		{
			const FDesignerNode* Child = FindNode(ChildId);
			if (!Child || !Child->bVisible)
			{
				continue;
			}
			MaxRow = (std::max)(MaxRow, Child->Row + (std::max)(1, Child->RowSpan));
			MaxColumn = (std::max)(MaxColumn, Child->Column + (std::max)(1, Child->ColumnSpan));
		}

		const float CellW = ParentGeometry.W / static_cast<float>((std::max)(1, MaxColumn));
		const float CellH = ParentGeometry.H / static_cast<float>((std::max)(1, MaxRow));
		for (int32 ChildId : Children)
		{
			const FDesignerNode* Child = FindNode(ChildId);
			if (!Child || !Child->bVisible)
			{
				continue;
			}
			const float SlotX = ParentGeometry.X + CellW * static_cast<float>((std::max)(0, Child->Column));
			const float SlotY = ParentGeometry.Y + CellH * static_cast<float>((std::max)(0, Child->Row));
			const float SlotW = CellW * static_cast<float>((std::max)(1, Child->ColumnSpan));
			const float SlotH = CellH * static_cast<float>((std::max)(1, Child->RowSpan));
			const float AvailableW = (std::max)(1.0f, SlotW - Child->PaddingLeft - Child->PaddingRight);
			const float AvailableH = (std::max)(1.0f, SlotH - Child->PaddingTop - Child->PaddingBottom);
			const float W = Child->SizeRule == ESizeRule::Fill ? AvailableW : (std::min)(Child->W, AvailableW);
			const float H = Child->SizeRule == ESizeRule::Fill ? AvailableH : (std::min)(Child->H, AvailableH);
			const float X = SlotX + Child->PaddingLeft + (AvailableW - W) * ClampFloat(Child->AlignmentX, 0.0f, 1.0f);
			const float Y = SlotY + Child->PaddingTop + (AvailableH - H) * ClampFloat(Child->AlignmentY, 0.0f, 1.0f);
			PushChild(*Child, X, Y, W, H);
		}
		return;
	}

	for (int32 ChildId : Children)
	{
		const FDesignerNode* Child = FindNode(ChildId);
		if (!Child || !Child->bVisible)
		{
			continue;
		}
		const float X = ParentGeometry.X + Child->X + Child->PaddingLeft;
		const float Y = ParentGeometry.Y + Child->Y + Child->PaddingTop;
		PushChild(*Child, X, Y, Child->W, Child->H);
	}
}

FString FRmlUiEditorWidget::GenerateRmlDocument() const
{
	std::ostringstream Out;
	Out << "<rml>\n";
	Out << "<head>\n";
	Out << "    <title>RmlUi Widget</title>\n";
	Out << "    <style>\n";
	Out << "        body { width: 100%; height: 100%; margin: 0; font-family: Maplestory; }\n";
	Out << "        .progress-fill { height: 100%; background-color: rgba(220, 70, 70, 1); }\n";
	for (const FDesignerAnimation& Animation : Animations)
	{
		if (Animation.Name.empty())
		{
			continue;
		}
		if (Animation.Tracks.empty())
		{
			if (Animation.TargetNodeId >= 0)
			{
				Out << "        @keyframes " << CssIdentifier(Animation.Name) << " { from { " << Animation.Property << ": " << Animation.FromValue
					<< "; } to { " << Animation.Property << ": " << Animation.ToValue << "; } }\n";
			}
			continue;
		}
		for (const FDesignerTrack& Track : Animation.Tracks)
		{
			if (Track.TargetNodeId < 0 || Track.Keys.empty())
			{
				continue;
			}
			TArray<FDesignerKeyframe> Keys = Track.Keys;
			std::stable_sort(Keys.begin(), Keys.end(),
				[](const FDesignerKeyframe& A, const FDesignerKeyframe& B) { return A.Time < B.Time; });
			const FString KeyframesName = CssIdentifier(Animation.Name + "_" + std::to_string(Track.Id));
			Out << "        @keyframes " << KeyframesName << " { ";
			for (const FDesignerKeyframe& Key : Keys)
			{
				const float Percent = ClampFloat(Key.Time / (std::max)(0.01f, Animation.Duration), 0.0f, 1.0f) * 100.0f;
				Out << Percent << "% { " << CssPropertyName(Track.Property) << ": " << CssAnimatedValue(Track.Property, Key.Value) << "; } ";
			}
			Out << "}\n";
		}
	}
	Out << "    </style>\n";
	Out << "</head>\n";
	Out << "<body>\n";

	TArray<int32> Children;
	CollectChildren(0, Children);
	for (int32 ChildId : Children)
	{
		AppendNodeRml(Out, ChildId, 1);
	}

	Out << "</body>\n";
	Out << "</rml>\n";
	return Out.str();
}

void FRmlUiEditorWidget::AppendNodeRml(std::ostringstream& Out, int32 NodeId, int32 Depth) const
{
	const FDesignerNode* Node = FindNode(NodeId);
	if (!Node || Node->Type == EWidgetType::Canvas || !Node->bVisible)
	{
		return;
	}

	const char* Tag = Node->Type == EWidgetType::Custom ? Node->CustomTag.c_str() : DefaultTagForType(Node->Type);
	Indent(Out, Depth);
	Out << "<" << Tag;
	if (!Node->ElementId.empty()) Out << " id=\"" << EscapeHtml(Node->ElementId) << "\"";
	if (!Node->ClassName.empty()) Out << " class=\"" << EscapeHtml(Node->ClassName) << "\"";
	if (Node->Type == EWidgetType::Image && !Node->ImageSource.empty()) Out << " src=\"" << EscapeHtml(Node->ImageSource) << "\"";
	if (Node->Type == EWidgetType::CheckBox) Out << " type=\"checkbox\"";

	const FDesignerNode* ParentNode = FindNode(Node->ParentId);
	const ESlotLayout ParentLayout = ParentNode ? ParentNode->SlotLayout : ESlotLayout::Canvas;
	const bool bAbsoluteSlot =
		ParentLayout == ESlotLayout::Canvas ||
		ParentLayout == ESlotLayout::Overlay ||
		ParentLayout == ESlotLayout::Grid;

	Out << " style=\"";
	if (bAbsoluteSlot)
	{
		Out << "position: absolute; left: " << Node->X + Node->PaddingLeft << "px; top: " << Node->Y + Node->PaddingTop << "px; ";
	}
	else
	{
		Out << "position: relative; margin: " << Node->PaddingTop << "px " << Node->PaddingRight << "px "
			<< Node->PaddingBottom << "px " << Node->PaddingLeft << "px; ";
		if (Node->SizeRule == ESizeRule::Fill)
		{
			Out << "flex: " << Node->FillWeight << "; ";
		}
	}
	Out << "width: " << Node->W << "px; height: " << Node->H << "px; ";
	Out << "z-index: " << Node->ZOrder << "; ";
	Out << "background-color: " << CssColor(Node->BackgroundColor) << "; ";
	Out << "color: " << CssColor(Node->TextColor) << "; ";
	Out << "font-size: " << Node->FontSize << "px; ";
	Out << "opacity: " << Node->Opacity << "; ";
	if (Node->SlotLayout == ESlotLayout::HorizontalBox)
	{
		Out << "display: flex; flex-direction: row; ";
	}
	else if (Node->SlotLayout == ESlotLayout::VerticalBox)
	{
		Out << "display: flex; flex-direction: column; ";
	}
	else if (Node->SlotLayout == ESlotLayout::Canvas || Node->SlotLayout == ESlotLayout::Overlay || Node->SlotLayout == ESlotLayout::Grid)
	{
		Out << "display: block; ";
		if (!bAbsoluteSlot && (Node->SlotLayout == ESlotLayout::Overlay || Node->SlotLayout == ESlotLayout::Grid))
		{
			Out << "position: relative; ";
		}
	}
	if (Node->BorderWidth > 0.0f)
	{
		Out << "border-width: " << Node->BorderWidth << "px; border-color: " << CssColor(Node->BorderColor) << "; ";
	}
	if (Node->Radius > 0.0f)
	{
		Out << "border-radius: " << Node->Radius << "px; ";
	}
	if (Node->bClipChildren)
	{
		Out << "overflow: hidden; ";
	}
	bool bHasAnimation = false;
	for (const FDesignerAnimation& Animation : Animations)
	{
		if (Animation.Name.empty())
		{
			continue;
		}
		if (Animation.Tracks.empty())
		{
			if (Animation.TargetNodeId == Node->Id)
			{
				if (!bHasAnimation)
				{
					Out << "animation: ";
					bHasAnimation = true;
				}
				else
				{
					Out << ", ";
				}
				Out << CssIdentifier(Animation.Name) << " " << Animation.Duration << "s linear " << AnimationIteration(Animation.bLoop);
			}
			continue;
		}
		for (const FDesignerTrack& Track : Animation.Tracks)
		{
			if (Track.TargetNodeId == Node->Id && !Track.Keys.empty())
			{
				if (!bHasAnimation)
				{
					Out << "animation: ";
					bHasAnimation = true;
				}
				else
				{
					Out << ", ";
				}
				Out << CssIdentifier(Animation.Name + "_" + std::to_string(Track.Id)) << " "
					<< Animation.Duration << "s linear " << AnimationIteration(Animation.bLoop);
			}
		}
	}
	if (bHasAnimation)
	{
		Out << "; ";
	}
	if (ParentLayout == ESlotLayout::Grid)
	{
		Out << "rml-grid-row: " << Node->Row << "; rml-grid-column: " << Node->Column
			<< "; rml-grid-row-span: " << Node->RowSpan << "; rml-grid-column-span: " << Node->ColumnSpan << "; ";
	}
	Out << "\"";

	if (Node->Type == EWidgetType::Image || Node->Type == EWidgetType::InputText || Node->Type == EWidgetType::CheckBox)
	{
		Out << " />\n";
		return;
	}

	Out << ">";
	if (Node->Type == EWidgetType::ProgressBar)
	{
		Out << "<div class=\"progress-fill\" style=\"width: 65%;\"></div>";
	}
	else
	{
		Out << EscapeHtml(Node->Text);
	}

	TArray<int32> Children;
	CollectChildren(Node->Id, Children);
	if (!Children.empty())
	{
		Out << "\n";
		for (int32 ChildId : Children)
		{
			AppendNodeRml(Out, ChildId, Depth + 1);
		}
		Indent(Out, Depth);
	}
	Out << "</" << Tag << ">\n";
}

int32 FRmlUiEditorWidget::HitTestDesignerNode(float LocalX, float LocalY) const
{
	for (auto It = CachedGeometries.rbegin(); It != CachedGeometries.rend(); ++It)
	{
		const FCachedGeometry& Geometry = *It;
		const FDesignerNode* Node = FindNode(Geometry.NodeId);
		if (!Node || Node->Type == EWidgetType::Canvas || !Node->bVisible || Node->bLocked)
		{
			continue;
		}
		if (LocalX < Geometry.X || LocalX > Geometry.X + Geometry.W || LocalY < Geometry.Y || LocalY > Geometry.Y + Geometry.H)
		{
			continue;
		}

		bool bVisibleThroughClip = true;
		int32 ParentId = Geometry.ParentId;
		while (ParentId >= 0)
		{
			const FDesignerNode* ParentNode = FindNode(ParentId);
			const FCachedGeometry* ParentGeometry = FindGeometry(ParentId);
			if (ParentNode && ParentGeometry && ParentNode->bClipChildren)
			{
				const bool bInsideClip =
					LocalX >= ParentGeometry->X &&
					LocalX <= ParentGeometry->X + ParentGeometry->W &&
					LocalY >= ParentGeometry->Y &&
					LocalY <= ParentGeometry->Y + ParentGeometry->H;
				if (!bInsideClip)
				{
					bVisibleThroughClip = false;
					break;
				}
			}
			ParentId = ParentGeometry ? ParentGeometry->ParentId : -1;
		}
		if (bVisibleThroughClip)
		{
			return Node->Id;
		}
	}
	return -1;
}
