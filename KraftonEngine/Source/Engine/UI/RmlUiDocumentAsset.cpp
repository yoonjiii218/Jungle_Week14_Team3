#include "UI/RmlUiDocumentAsset.h"

#include "Serialization/Archive.h"

#include <sstream>

namespace
{
	const char* DefaultRmlUiDocument =
		"<rml>\n"
		"<head>\n"
		"    <title>RmlUi Widget</title>\n"
		"    <style>\n"
		"        body { width: 100%; height: 100%; margin: 0; font-family: Maplestory; }\n"
		"    </style>\n"
		"</head>\n"
		"<body>\n"
		"    <div id=\"root\" style=\"position: absolute; left: 0px; top: 0px; width: 1280px; height: 720px;\"></div>\n"
		"</body>\n"
		"</rml>\n";

	void AppendDesignerNodeState(
		std::ostringstream& Out,
		int32 Id,
		int32 ParentId,
		int32 Type,
		const char* Name,
		const char* ElementId,
		const char* ClassName,
		float X,
		float Y,
		float W,
		float H,
		bool bClipChildren,
		float BackgroundAlpha)
	{
		Out << "NODE"
			<< "\t" << Id
			<< "\t" << ParentId
			<< "\t" << Type
			<< "\t" << Name
			<< "\t" << ElementId
			<< "\t" << ClassName
			<< "\t"
			<< "\t"
			<< "\tdiv"
			<< "\t" << X
			<< "\t" << Y
			<< "\t" << W
			<< "\t" << H
			<< "\t0"
			<< "\t0"
			<< "\t18"
			<< "\t1"
			<< "\t1"
			<< "\t0"
			<< "\t" << (bClipChildren ? 1 : 0)
			<< "\t0"
			<< "\t0"
			<< "\t0"
			<< "\t0"
			<< "\t0"
			<< "\t0"
			<< "\t0"
			<< "\t0"
			<< "\t1"
			<< "\t0"
			<< "\t0"
			<< "\t1"
			<< "\t1"
			<< "\t0"
			<< "\t0.02"
			<< "\t0.02"
			<< "\t0.025"
			<< "\t" << BackgroundAlpha
			<< "\t1"
			<< "\t1"
			<< "\t1"
			<< "\t1"
			<< "\t1"
			<< "\t1"
			<< "\t1"
			<< "\t0.35"
			<< "\n";
	}

	FString MakeDefaultDesignerState()
	{
		std::ostringstream Out;
		Out << "RMLUI_DESIGNER_STATE\t1\n";
		Out << "CANVAS\t1280\t720\t2\t1\n";
		AppendDesignerNodeState(Out, 0, -1, 0, "Canvas", "canvas", "Canvas", 0.0f, 0.0f, 1280.0f, 720.0f, false, 1.0f);
		AppendDesignerNodeState(Out, 1, 0, 1, "Root Canvas", "root", "RootCanvas", 0.0f, 0.0f, 1280.0f, 720.0f, true, 0.0f);
		return Out.str();
	}
}

void URmlUiDocumentAsset::InitializeDefault()
{
	DocumentSource = DefaultRmlUiDocument;
	DesignerState = MakeDefaultDesignerState();
}

void URmlUiDocumentAsset::Serialize(FArchive& Ar)
{
	UObject::Serialize(Ar);
	Ar << DocumentSource;
	Ar << DesignerState;
}
