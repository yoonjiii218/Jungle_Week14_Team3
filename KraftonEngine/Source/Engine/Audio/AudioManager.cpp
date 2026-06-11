#include "AudioManager.h"
#include "Core/Logging/Log.h"
#include "Platform/Paths.h"
#include <algorithm>

namespace
{
	constexpr size_t MaxOneShotChannels = 256;

	float ClampVolumeFloor(float Volume)
	{
		return Volume < 0.0f ? 0.0f : Volume;
	}

	float ClampPitchFloor(float Pitch)
	{
		return Pitch < 0.1f ? 0.1f : Pitch;
	}

}

bool FAudioManager::Initialize()
{
	if (FMOD::System_Create(&System) != FMOD_OK || !System)
	{
		UE_LOG("Failed to create FMOD system.");
		return false;
	}

	if (System->init(512, FMOD_INIT_NORMAL, nullptr) != FMOD_OK)
	{
		UE_LOG("Failed to initialize FMOD system.");
		Shutdown();
		return false;
	}

	System->getMasterChannelGroup(&MasterGroup);

	LoadDefaultAudios();

	return true;
}

void FAudioManager::Shutdown()
{
	if (!System)
	{
		MasterGroup = nullptr;
		BGMChannel = nullptr;
		LoopChannels.clear();
		OneShotChannels.clear();
		Audios.clear();
		return;
	}

	StopBGM();
	StopAllLoops();
	for (const FOneShotChannel& Entry : OneShotChannels)
	{
		if (Entry.Channel)
		{
			Entry.Channel->stop();
		}
	}
	OneShotChannels.clear();

	if (MasterGroup)
	{
		MasterGroup->stop();
		MasterGroup = nullptr;
	}
	System->update();

	for (auto& Pair : Audios)
	{
		if (Pair.second)
		{
			Pair.second->release();
		}
	}
	Audios.clear();

	System->update();
	System->close();
	System->release();
	System = nullptr;
}

void FAudioManager::Tick()
{
	if (System)
	{
		System->update();
		CleanupOneShotChannels();
	}
}

bool FAudioManager::LoadAudio(const FString& Key, const FString& Path, bool bLoop)
{
	if (!System)
	{
		return false;
	}

	FString FullPath = FPaths::ToUtf8(FPaths::Combine(FPaths::AudioDir(), FPaths::ToWide(Path)));

	FMOD::Sound* Sound = nullptr;
	const FMOD_MODE Mode = FMOD_DEFAULT | (bLoop ? FMOD_LOOP_NORMAL : FMOD_LOOP_OFF);

	if (System->createSound(FullPath.c_str(), Mode, nullptr, &Sound) != FMOD_OK)
	{
		return false;
	}

	if (Audios.contains(Key) && Audios[Key])
	{
		Audios[Key]->release();
	}

	Audios[Key] = Sound;
	return true;
}

void FAudioManager::PlayAudio(const FString& Key, float Volume, float Pitch, int MaxInstances)
{
	if (!System)
	{
		return;
	}

	const auto It = Audios.find(Key);
	if (It == Audios.end() || !It->second)
	{
		return;
	}

	CleanupOneShotChannels();
	if (MaxInstances > 0)
	{
		int MatchingInstances = 0;
		auto OldestMatching = OneShotChannels.end();
		for (auto It = OneShotChannels.begin(); It != OneShotChannels.end(); ++It)
		{
			if (It->Key == Key)
			{
				if (OldestMatching == OneShotChannels.end())
				{
					OldestMatching = It;
				}
				++MatchingInstances;
			}
		}

		if (MatchingInstances >= MaxInstances && OldestMatching != OneShotChannels.end())
		{
			if (OldestMatching->Channel)
			{
				OldestMatching->Channel->stop();
			}
			OneShotChannels.erase(OldestMatching);
		}
	}

	if (OneShotChannels.size() >= MaxOneShotChannels)
	{
		if (FMOD::Channel* OldestChannel = OneShotChannels.front().Channel)
		{
			OldestChannel->stop();
		}
		OneShotChannels.erase(OneShotChannels.begin());
	}

	FMOD::Channel* Channel = nullptr;
	FMOD_RESULT Result = System->playSound(It->second, nullptr, false, &Channel);

	if (Result != FMOD_OK)
	{
		System->update();
		CleanupOneShotChannels();

		if (!OneShotChannels.empty())
		{
			if (FMOD::Channel* OldestChannel = OneShotChannels.front().Channel)
			{
				OldestChannel->stop();
			}
			OneShotChannels.erase(OneShotChannels.begin());
			Result = System->playSound(It->second, nullptr, false, &Channel);
		}
	}

	if (Result == FMOD_OK && Channel)
	{
		Channel->setVolume(ClampVolumeFloor(Volume));
		Channel->setPitch(ClampPitchFloor(Pitch));
		OneShotChannels.push_back({ Key, Channel });
	}
}

void FAudioManager::PlayBGM(const FString& Key, float Volume, float Pitch)
{
	if (!System || !Audios.contains(Key))
	{
		return;
	}

	StopBGM();
	System->playSound(Audios[Key], nullptr, false, &BGMChannel);

	if (BGMChannel)
	{
		BGMChannel->setVolume(ClampVolumeFloor(Volume));
		BGMChannel->setPitch(ClampPitchFloor(Pitch));
	}
}

void FAudioManager::StopBGM()
{
	if (BGMChannel)
	{
		BGMChannel->stop();
		BGMChannel = nullptr;
	}
}

void FAudioManager::SetBGMPitch(float Pitch)
{
	if (BGMChannel)
	{
		BGMChannel->setPitch(ClampPitchFloor(Pitch));
	}
}

void FAudioManager::PlayLoop(const FString& Key, const FString& LoopName, float Volume, float Pitch)
{
	if (!System || !Audios.contains(Key) || LoopName.empty())
	{
		return;
	}

	if (FMOD::Channel* ExistingChannel = FindPlayingLoopChannel(LoopName))
	{
		ExistingChannel->setVolume(ClampVolumeFloor(Volume));
		ExistingChannel->setPitch(ClampPitchFloor(Pitch));
		return;
	}

	FMOD::Channel* Channel = nullptr;
	System->playSound(Audios[Key], nullptr, false, &Channel);

	if (Channel)
	{
		Channel->setMode(FMOD_LOOP_NORMAL);
		Channel->setVolume(ClampVolumeFloor(Volume));
		Channel->setPitch(ClampPitchFloor(Pitch));
		LoopChannels[LoopName] = Channel;
	}
}

void FAudioManager::StopLoop(const FString& LoopName)
{
	if (!LoopChannels.contains(LoopName))
	{
		return;
	}

	if (LoopChannels[LoopName])
	{
		LoopChannels[LoopName]->stop();
	}
	LoopChannels.erase(LoopName);
}

void FAudioManager::StopAllLoops()
{
	for (auto& Pair : LoopChannels)
	{
		if (Pair.second)
		{
			Pair.second->stop();
		}
	}
	LoopChannels.clear();
}

void FAudioManager::SetLoopVolume(const FString& LoopName, float Volume)
{
	if (FMOD::Channel* Channel = FindPlayingLoopChannel(LoopName))
	{
		Channel->setVolume(ClampVolumeFloor(Volume));
	}
}

void FAudioManager::SetLoopPitch(const FString& LoopName, float Pitch)
{
	if (FMOD::Channel* Channel = FindPlayingLoopChannel(LoopName))
	{
		Channel->setPitch(ClampPitchFloor(Pitch));
	}
}

bool FAudioManager::IsLoopPlaying(const FString& LoopName)
{
	return FindPlayingLoopChannel(LoopName) != nullptr;
}

bool FAudioManager::IsAudioLoaded(const FString& Key) const
{
	const auto It = Audios.find(Key);
	return It != Audios.end() && It->second != nullptr;
}

void FAudioManager::CleanupOneShotChannels()
{
	OneShotChannels.erase(
		std::remove_if(
			OneShotChannels.begin(),
			OneShotChannels.end(),
			[](const FOneShotChannel& Entry)
			{
				bool bIsPlaying = false;
				return !Entry.Channel || Entry.Channel->isPlaying(&bIsPlaying) != FMOD_OK || !bIsPlaying;
			}),
		OneShotChannels.end());
}

FMOD::Channel* FAudioManager::FindPlayingLoopChannel(const FString& LoopName)
{
	if (!LoopChannels.contains(LoopName))
	{
		return nullptr;
	}

	FMOD::Channel* Channel = LoopChannels[LoopName];
	bool bIsPlaying = false;
	if (!Channel || Channel->isPlaying(&bIsPlaying) != FMOD_OK || !bIsPlaying)
	{
		LoopChannels.erase(LoopName);
		return nullptr;
	}

	return Channel;
}

void FAudioManager::SetMasterVolume(float Volume)
{
	if (MasterGroup)
	{
		MasterGroup->setVolume(ClampVolumeFloor(Volume));
	}
}

void FAudioManager::LoadDefaultAudios()
{
	LoadAudio("CityBgm", "city_bgm.mp3", true);
	LoadAudio("Phase_EscapePolice", "phase_escapepolice.wav", true);
	LoadAudio("Phase_Meteor", "phase_meteor.mp3", true);
	LoadAudio("Click", "pop.mp3");
	LoadAudio("CarEngineLoop", "car_engine_loop.mp3", true);
	LoadAudio("Notify", "notify.mp3");
	LoadAudio("Complete", "complete.mp3");
	LoadAudio("Crash", "crash.mp3");
	LoadAudio("Water", "water.mp3", true);
	LoadAudio("Siren", "siren.mp3", true);
	LoadAudio("Fueling", "fueling.mp3", true);
	LoadAudio("ScoreUp", "score_up.mp3");
	LoadAudio("MeteorBoom", "meteor_boom.mp3");
	LoadAudio("MeteorFall", "meteor_fall.mp3");
	LoadAudio("Whoosh", "whoosh.mp3");
}
