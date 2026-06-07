#include "AnimSequencePropertyPanel.h"

#include "Animation/Sequence/AnimSequence.h"
#include "Animation/AnimationManager.h"
#include "Animation/Sequence/BoneAnimationTrack.h"

#include <imgui.h>

namespace
{

	void RenderPoseAdjustmentSection(UAnimSequence* Seq)
	{
		ImGui::TextUnformatted("Pose Adjustment");
		ImGui::Separator();

		float GroundZOffset = Seq->GetGroundZOffset();
		ImGui::SetNextItemWidth(-1.0f);
		if (ImGui::DragFloat("Ground Z Offset", &GroundZOffset, 0.1f, -10000.0f, 10000.0f, "%.3f"))
		{
			Seq->SetGroundZOffset(GroundZOffset);
		}
		if (ImGui::IsItemDeactivatedAfterEdit())
		{
			FAnimationManager::Get().SaveAnimationPreservingMetadata(Seq);
		}
		if (ImGui::IsItemHovered())
		{
			ImGui::SetTooltip("Evaluated pose 의 skeleton root local Z 에 더해지는 per-sequence 보정값입니다.\nForce Root Lock / Root Motion 처리 후 적용됩니다.");
		}
	}
	void RenderRootMotionSection(UAnimSequence* Seq)
	{
		ImGui::TextUnformatted("Root Motion");
		ImGui::Separator();

		// Force Root Lock — horizontal 만 잠금 (in-place 걷기), vertical Z 는 anim 유지.
		bool bLock = Seq->GetForceRootLock();
		if (ImGui::Checkbox("Force Root Lock", &bLock))
		{
			Seq->SetForceRootLock(bLock);
			if (bLock) Seq->SetEnableRootMotion(false);   // mutex
			FAnimationManager::Get().SaveAnimationPreservingMetadata(Seq);
		}
		if (ImGui::IsItemHovered())
		{
			ImGui::SetTooltip("Root motion 본의 horizontal (X/Y) translation 을 잠가\nin-place 재생. Z (vertical bobbing) 는 유지.");
		}

		// Enable Root Motion — translation/rotation 을 actor 의 world transform 에 반영.
		bool bRootMotion = Seq->GetEnableRootMotion();
		if (ImGui::Checkbox("Enable Root Motion", &bRootMotion))
		{
			Seq->SetEnableRootMotion(bRootMotion);   // bForceRootLock 자동 해제 (setter 안)
			FAnimationManager::Get().SaveAnimationPreservingMetadata(Seq);
		}
		if (ImGui::IsItemHovered())
		{
			ImGui::SetTooltip("Root motion 본의 translation/rotation 을 본 pose 에서 제거하고\nowning actor 의 transform 에 반영 (캐릭터가 anim 으로 world 이동).");
		}

		// Root motion 본 선택 콤보 — 둘 중 하나라도 켜져 있을 때만 노출.
		const bool bShowBoneCombo = bLock || bRootMotion;
		if (bShowBoneCombo)
		{
			ImGui::Dummy(ImVec2(0.0f, 4.0f));
			ImGui::TextUnformatted("Root Motion Bone");
			ImGui::SetNextItemWidth(-1.0f);

			const FString& Current = Seq->GetRootMotionBoneName();
			const char* CurrentLabel = Current.empty() ? "(none)" : Current.c_str();
			if (ImGui::BeginCombo("##rootMotionBone", CurrentLabel))
			{
				if (ImGui::Selectable("(none)", Current.empty()))
				{
					Seq->SetRootMotionBoneName(FString());
					FAnimationManager::Get().SaveAnimationPreservingMetadata(Seq);
				}
				for (const FBoneAnimationTrack& Track : Seq->GetBoneTracks())
				{
					if (Track.BoneName.empty()) continue;
					const bool bSelected = (Track.BoneName == Current);
					if (ImGui::Selectable(Track.BoneName.c_str(), bSelected))
					{
						Seq->SetRootMotionBoneName(Track.BoneName);
						FAnimationManager::Get().SaveAnimationPreservingMetadata(Seq);
					}
					if (bSelected) ImGui::SetItemDefaultFocus();
				}
				ImGui::EndCombo();
			}
		}
	}
}

void FAnimSequencePropertyPanel::Render(UAnimSequence* Seq)
{
	if (!Seq)
	{
		ImGui::TextDisabled("No animation selected.");
		return;
	}

	RenderPoseAdjustmentSection(Seq);
	ImGui::Dummy(ImVec2(0.0f, 8.0f));
	RenderRootMotionSection(Seq);
	// 향후 추가 section 은 여기에 ImGui::Dummy + 호출 추가.
}
