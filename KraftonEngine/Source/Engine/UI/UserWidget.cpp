#include "UI/UserWidget.h"

#include "Object/Reflection/ObjectFactory.h"
#include "UI/UIManager.h"

void UUserWidget::BeginDestroy()
{
    if (HasAnyFlags(RF_BeginDestroy))
    {
        return;
    }

    RemoveFromParent();
    ClearEventListeners();
    PendingEventBindings.clear();
    ClearDocument();

    OwningPlayer.Reset();

    UObject::BeginDestroy();
}

void UUserWidget::AddReferencedObjects(FReferenceCollector& Collector)
{
    UObject::AddReferencedObjects(Collector);
}

void UUserWidget::Initialize(APlayerController* InOwningPlayer, const FString& InDocumentPath)
{
	OwningPlayer = InOwningPlayer;
	DocumentPath = InDocumentPath;
}

void UUserWidget::AddToViewport(int32 InZOrder)
{
	ZOrder = InZOrder;
	bInViewport = true;
	UUIManager::Get().AddToViewport(this, InZOrder);
}

void UUserWidget::RemoveFromParent()
{
	UUIManager::Get().RemoveFromViewport(this);
	bInViewport = false;
}

void UUserWidget::BindClick(const FString& ElementId, sol::protected_function Callback)
{
	BindEvent(ElementId, "click", std::move(Callback));
}

void UUserWidget::BindEvent(const FString& ElementId, const FString& EventName, sol::protected_function Callback)
{
	PendingEventBindings.push_back({ ElementId, EventName, Callback });
	if (IsDocumentLoaded())
	{
		RegisterEventListeners();
	}
}

void UUserWidget::RegisterEventListeners()
{
	if (!Document)
	{
		return;
	}

	ClearEventListeners();

	for (const FWidgetEventBinding& Binding : PendingEventBindings)
	{
		Rml::Element* Element = Document->GetElementById(Binding.ElementId);
		if (!Element)
		{
			UE_LOG("[RmlUi] Event target not found: %s", Binding.ElementId.c_str());
			continue;
		}

		auto* Listener = new FWidgetEventListener(Binding.ElementId, Binding.EventName, Binding.Callback);
		Element->AddEventListener(Binding.EventName.c_str(), Listener);
		EventListeners.push_back(Listener);
	}
}

void UUserWidget::ClearEventListeners()
{
	if (Document)
	{
		for (FWidgetEventListener* Listener : EventListeners)
		{
			if (!Listener)
			{
				continue;
			}

			Rml::Element* Element = Document->GetElementById(Listener->GetElementId());
			if (Element)
			{
				Element->RemoveEventListener(Listener->GetEventName().c_str(), Listener);
			}
		}
	}

	for (FWidgetEventListener* Listener : EventListeners)
	{
		delete Listener;
	}
	EventListeners.clear();
}

void UUserWidget::SetText(const FString& ElementId, const FString& Text)
{
	if (!Document)
	{
		return;
	}

	Rml::Element* Element = Document->GetElementById(ElementId);
	if (!Element)
	{
		UE_LOG("[RmlUi] Text target not found: %s", ElementId.c_str());
		return;
	}

	Element->SetInnerRML(Text.c_str());
}

bool UUserWidget::SetProperty(const FString& ElementId, const FString& PropertyName, const FString& Value)
{
	if (!Document)
	{
		return false;
	}

	Rml::Element* Element = Document->GetElementById(ElementId);
	if (!Element)
	{
		UE_LOG("[RmlUi] Property target not found: %s", ElementId.c_str());
		return false;
	}

	return Element->SetProperty(PropertyName.c_str(), Value.c_str());
}
