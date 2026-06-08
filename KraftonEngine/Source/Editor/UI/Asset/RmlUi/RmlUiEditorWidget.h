#pragma once

#include "Editor/UI/Asset/AssetEditorWidget.h"

#include <string>

class URmlUiDocumentAsset;

class FRmlUiEditorWidget : public FAssetEditorWidget
{
public:
	struct FElementInfo
	{
		FString Tag;
		FString Id;
		int32 Depth = 0;
		bool bClosing = false;
		bool bSelfClosing = false;
	};

	enum class EDesignerWidgetType : int32
	{
		Canvas,
		Panel,
		Text,
		Button,
		Image,
		ProgressBar,
		InputText,
		CheckBox,
		Slider,
		List,
		Custom
	};

	enum class EDesignerSlotLayout : int32
	{
		Canvas,
		Overlay,
		HorizontalBox,
		VerticalBox,
		Grid
	};

	enum class EDesignerSizeRule : int32
	{
		Auto,
		Fill
	};

	enum class EDesignerAnimProperty : int32
	{
		Opacity,
		X,
		Y,
		Width,
		Height,
		Rotation,
		Scale
	};

	struct FDesignerColor
	{
		float R = 1.0f;
		float G = 1.0f;
		float B = 1.0f;
		float A = 1.0f;
	};

	struct FDesignerNode
	{
		int32 Id = 0;
		int32 ParentId = -1;
		EDesignerWidgetType Type = EDesignerWidgetType::Panel;
		FString Name;
		FString ElementId;
		FString ClassName;
		FString Text;
		FString ImageSource;
		FString CustomTag = "div";
		float X = 0.0f;
		float Y = 0.0f;
		float W = 160.0f;
		float H = 48.0f;
		float AnchorMinX = 0.0f;
		float AnchorMinY = 0.0f;
		float AnchorMaxX = 0.0f;
		float AnchorMaxY = 0.0f;
		float BorderWidth = 0.0f;
		float Radius = 0.0f;
		int32 FontSize = 18;
		float Opacity = 1.0f;
		bool bVisible = true;
		bool bLocked = false;
		bool bClipChildren = false;
		EDesignerSlotLayout SlotLayout = EDesignerSlotLayout::Canvas;
		EDesignerSizeRule SizeRule = EDesignerSizeRule::Auto;
		float PaddingLeft = 0.0f;
		float PaddingTop = 0.0f;
		float PaddingRight = 0.0f;
		float PaddingBottom = 0.0f;
		float AlignmentX = 0.0f;
		float AlignmentY = 0.0f;
		float FillWeight = 1.0f;
		int32 Row = 0;
		int32 Column = 0;
		int32 RowSpan = 1;
		int32 ColumnSpan = 1;
		int32 ZOrder = 0;
		FDesignerColor BackgroundColor { 0.08f, 0.08f, 0.09f, 0.78f };
		FDesignerColor TextColor { 1.0f, 1.0f, 1.0f, 1.0f };
		FDesignerColor BorderColor { 1.0f, 1.0f, 1.0f, 0.35f };
	};

	struct FDesignerKeyframe
	{
		float Time = 0.0f;
		float Value = 0.0f;
	};

	struct FDesignerTrack
	{
		int32 Id = 0;
		int32 TargetNodeId = -1;
		EDesignerAnimProperty Property = EDesignerAnimProperty::Opacity;
		TArray<FDesignerKeyframe> Keys;
		bool bExpanded = true;
	};

	struct FDesignerAnimation
	{
		FString Name = "FadeIn";
		int32 TargetNodeId = -1;
		FString Property = "opacity";
		float FromValue = 0.0f;
		float ToValue = 1.0f;
		float Duration = 0.25f;
		bool bLoop = false;
		TArray<FDesignerTrack> Tracks;
	};

	struct FDesignerSnapshot
	{
		TArray<FDesignerNode> Nodes;
		TArray<FDesignerAnimation> Animations;
		int32 SelectedNodeId = 0;
		int32 NextNodeId = 1;
		int32 NextTrackId = 1;
	};

	struct FCachedGeometry
	{
		int32 NodeId = -1;
		int32 ParentId = -1;
		float X = 0.0f;
		float Y = 0.0f;
		float W = 0.0f;
		float H = 0.0f;
		int32 ZOrder = 0;
		int32 Layer = 0;
		bool bClipped = false;
	};

	FRmlUiEditorWidget() = default;
	~FRmlUiEditorWidget() override = default;

	bool CanEdit(UObject* Object) const override;
	bool AllowsMultipleInstances() const override { return true; }
	bool IsEditingObject(UObject* Object) const override;
	void Open(UObject* Object) override;
	void Close() override;
	void Render(float DeltaTime) override;

private:
	URmlUiDocumentAsset* GetDocumentAsset() const;
	bool LoadFromDisk(bool bForceReload = false);
	bool SaveToDisk();
	void RenderMenuBar();
	void RenderToolbar();
	void RenderSourceEditor();
	void RenderDesigner();
	void RenderPalette();
	void RenderHierarchy();
	void RenderHierarchyNode(int32 NodeId);
	void RenderDesignerSurface();
	void RenderDetails();
	void RenderOutline();
	void RenderBindings();
	void RenderPreviewSettings();
	void RenderAnimations();
	void RenderTemplates();
	void RebuildAnalysis();
	void RebuildDesignerFromSource();
	void SyncSourceFromDesigner();
	FString SerializeDesignerState() const;
	bool DeserializeDesignerState(const FString& State);
	void InsertTemplate(const char* Text);
	void PushUndoSnapshot();
	void RestoreSnapshot(const FDesignerSnapshot& Snapshot);
	void Undo();
	void Redo();
	void MarkDesignerChanged();
	void EnsureDesignerModel();
	void ClearDesignerModel();
	FDesignerNode* FindNode(int32 NodeId);
	const FDesignerNode* FindNode(int32 NodeId) const;
	FCachedGeometry* FindGeometry(int32 NodeId);
	const FCachedGeometry* FindGeometry(int32 NodeId) const;
	int32 AddDesignerNode(EDesignerWidgetType Type, int32 ParentId, float X, float Y);
	void DeleteDesignerNode(int32 NodeId);
	void DuplicateDesignerNode(int32 NodeId);
	void ReparentDesignerNode(int32 NodeId, int32 NewParentId);
	bool IsDescendantOf(int32 NodeId, int32 PossibleParentId) const;
	void CollectChildren(int32 ParentId, TArray<int32>& OutChildren) const;
	void RebuildGeometryCache();
	void BuildChildGeometries(int32 ParentId, const FCachedGeometry& ParentGeometry, int32 Layer);
	void BuildHitTestPath(int32 NodeId, TArray<int32>& OutPath) const;
	FString GenerateRmlDocument() const;
	void AppendNodeRml(std::ostringstream& Out, int32 NodeId, int32 Depth) const;
	int32 HitTestDesignerNode(float LocalX, float LocalY) const;

private:
	std::string SourceBuffer;
	TArray<FElementInfo> Elements;
	TArray<FString> ElementIds;
	TArray<FDesignerNode> DesignerNodes;
	TArray<FDesignerAnimation> Animations;
	TArray<FCachedGeometry> CachedGeometries;
	TArray<int32> LastHitTestPath;
	TArray<FDesignerSnapshot> UndoStack;
	TArray<FDesignerSnapshot> RedoStack;
	FDesignerNode ClipboardNode;
	FString LastError;
	FString StatusMessage;
	int32 SelectedNodeId = 0;
	int32 SelectedAnimationIndex = -1;
	int32 SelectedTrackId = -1;
	int32 SelectedKeyIndex = -1;
	int32 NextNodeId = 1;
	int32 NextTrackId = 1;
	int32 DraggingNodeId = -1;
	int32 ResizingNodeId = -1;
	float DragStartMouseX = 0.0f;
	float DragStartMouseY = 0.0f;
	float DragStartNodeX = 0.0f;
	float DragStartNodeY = 0.0f;
	float DragStartNodeW = 0.0f;
	float DragStartNodeH = 0.0f;
	float DesignerZoom = 1.0f;
	float TimelineZoom = 1.0f;
	float TimelinePlayhead = 0.0f;
	float CanvasWidth = 1280.0f;
	float CanvasHeight = 720.0f;
	bool bShowGrid = true;
	bool bSnapToGrid = true;
	bool bHasClipboardNode = false;
	bool bLoaded = false;
	bool bAnalysisDirty = true;
	bool bDesignerDirty = true;
	bool bSyncingSourceFromDesigner = false;
	bool bSourceOnlyDocument = false;
};
