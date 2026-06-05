#include "AnimDataModel.h"
#include "Object/GarbageCollection.h"

#include <algorithm>

namespace
{
    constexpr int32 NotifyTrackMagic = 0x4E54524B; // "NTRK"
    constexpr int32 NotifyTrackVersion = 1;
}

void UAnimDataModel::AddReferencedObjects(FReferenceCollector& Collector)
{
    UObject::AddReferencedObjects(Collector);

    for (const FAnimNotifyEvent& Notify : Notifies)
    {
        Notify.AddReferencedObjects(Collector);
    }
}

void UAnimDataModel::Serialize(FArchive& Ar)
{
    UObject::Serialize(Ar);

    Ar << PlayLength;
    Ar << FrameRate;
    Ar << NumFrames;
    Ar << BoneAnimationTracks;

    // Morph curves are authored data owned by this animation. They are appended before notifies.
    Ar << MorphTargetCurves;

    // Notifies 는 Outer 인지 직렬화 — Notify/NotifyState 객체 클래스명 + UPROPERTY(Save) payload
    // 까지 round-trip. ObjectFactory::Create 가 Outer 를 받아야 라이프타임 체인 형성되므로
    // TArray operator<< (raw 만) 사용 못 함, 명시적 루프로 entry 별 Serialize(Ar, this) 호출.
    int32 NotifyCount = static_cast<int32>(Notifies.size());
    Ar << NotifyCount;
    if (Ar.IsLoading())
    {
        Notifies.clear();
        Notifies.resize(NotifyCount);
    }
    for (int32 i = 0; i < NotifyCount; ++i)
    {
        Notifies[i].Serialize(Ar, this);
    }

    if (Ar.IsSaving())
    {
        int32 Magic = NotifyTrackMagic;
        int32 Version = NotifyTrackVersion;
        Ar << Magic;
        Ar << Version;
        Ar << NotifyTracks;

        int32 TrackIndexCount = static_cast<int32>(Notifies.size());
        Ar << TrackIndexCount;
        for (FAnimNotifyEvent& Notify : Notifies)
        {
            Ar << Notify.TrackIndex;
        }
    }
    else if (Ar.HasRemaining())
    {
        int32 Magic = 0;
        Ar << Magic;
        if (Magic == NotifyTrackMagic)
        {
            int32 Version = 0;
            Ar << Version;
            if (Version == NotifyTrackVersion)
            {
                Ar << NotifyTracks;

                int32 TrackIndexCount = 0;
                Ar << TrackIndexCount;
                const int32 Count = std::min(TrackIndexCount, static_cast<int32>(Notifies.size()));
                for (int32 i = 0; i < Count; ++i)
                {
                    Ar << Notifies[i].TrackIndex;
                }
                for (int32 i = Count; i < TrackIndexCount; ++i)
                {
                    int32 IgnoredTrackIndex = 0;
                    Ar << IgnoredTrackIndex;
                }
            }
        }
    }

    EnsureNotifyTrackLayout();
}

void UAnimDataModel::EnsureNotifyTrackLayout()
{
    if (NotifyTracks.empty())
    {
        FAnimNotifyTrack DefaultTrack;
        DefaultTrack.TrackName = FName("1");
        NotifyTracks.push_back(DefaultTrack);
    }

    const int32 MaxTrackIndex = static_cast<int32>(NotifyTracks.size()) - 1;
    for (FAnimNotifyEvent& Notify : Notifies)
    {
        Notify.TrackIndex = std::clamp(Notify.TrackIndex, 0, MaxTrackIndex);
    }
}
