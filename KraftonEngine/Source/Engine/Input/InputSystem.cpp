#include "Engine/Input/InputSystem.h"
#include <Xinput.h>
#include <cmath>

#pragma comment(lib, "xinput9_1_0.lib")

namespace
{
    constexpr float StickDeadzoneNormalized = 0.20f;
    constexpr float TriggerDownThreshold = 0.25f;
    constexpr float TriggerUpThreshold = 0.15f;

    int32 ToIndex(EGamepadButton Button)
    {
        return static_cast<int32>(Button);
    }

    int32 ToIndex(EGamepadAxis Axis)
    {
        return static_cast<int32>(Axis);
    }

    float ApplyDeadzone(float Value, float Deadzone)
    {
        const float AbsValue = std::fabs(Value);
        if (AbsValue <= Deadzone)
        {
            return 0.0f;
        }

        const float Sign = Value >= 0.0f ? 1.0f : -1.0f;
        const float Scaled = (AbsValue - Deadzone) / (1.0f - Deadzone);
        return Sign * Scaled;
    }

    float NormalizeThumbAxis(SHORT Value)
    {
        const float Denom = Value < 0 ? 32768.0f : 32767.0f;
        return ApplyDeadzone(static_cast<float>(Value) / Denom, StickDeadzoneNormalized);
    }

    float NormalizeTrigger(BYTE Value)
    {
        return static_cast<float>(Value) / 255.0f;
    }

    void SetButton(FGamepadSnapshot& Pad, EGamepadButton Button, bool bDown)
    {
        Pad.ButtonDown[ToIndex(Button)] = bDown;
    }

    void SetAxis(FGamepadSnapshot& Pad, EGamepadAxis Axis, float Value)
    {
        Pad.Axes[ToIndex(Axis)] = Value;
    }

    bool EvaluateTriggerButton(float AxisValue, bool bWasDown)
    {
        return bWasDown ? AxisValue > TriggerUpThreshold : AxisValue >= TriggerDownThreshold;
    }
}

void InputSystem::Tick()
{
    // 윈도우 포커스가 없으면 모든 입력 상태 해제
    bWindowFocused = !OwnerHWnd || GetForegroundWindow() == OwnerHWnd;
    if (!bWindowFocused)
    {
        ResetAllKeyStates();
        ResetGamepadStates();
        ResetTransientState();
        UpdateCurrentSnapshot();
        return;
    }

    for (int32 PadIndex = 0; PadIndex < FInputSystemSnapshot::MaxGamepads; ++PadIndex)
    {
        PrevGamepads[PadIndex] = CurrentGamepads[PadIndex];
    }
    PollGamepads();

    for (int i = 0; i < 256; ++i)
    {
        PrevStates[i] = CurrentStates[i];
        CurrentStates[i] = (GetAsyncKeyState(i) & 0x8000) != 0;
    }

    bLeftDragJustStarted = false;
    bRightDragJustStarted = false;
    bLeftDragJustEnded = false;
    bRightDragJustEnded = false;

    PrevScrollDelta = ScrollDelta;
    ScrollDelta = 0;

    PrevMousePos = MousePos;
    GetCursorPos(&MousePos);
    FrameMouseDeltaX = MousePos.x - PrevMousePos.x;
    FrameMouseDeltaY = MousePos.y - PrevMousePos.y;
    if (bUseRawMouse)
    {
        FrameMouseDeltaX = RawMouseDeltaAccumX;
        FrameMouseDeltaY = RawMouseDeltaAccumY;
    }
    RawMouseDeltaAccumX = 0;
    RawMouseDeltaAccumY = 0;

    if (GetKeyDown(VK_LBUTTON))
    {
        bLeftDragCandidate = true;
        LeftMouseDownPos = MousePos;
    }
    if (GetKeyDown(VK_RBUTTON))
    {
        bRightDragCandidate = true;
        RightMouseDownPos = MousePos;
    }

    // Left drag
    if (!bLeftDragging && IsDraggingLeft())
    {
        FilterDragThreshold(bLeftDragCandidate, bLeftDragging, bLeftDragJustStarted,
            LeftMouseDownPos, LeftDragStartPos);
    }
    else if (GetKeyUp(VK_LBUTTON))
    {
        if (bLeftDragging) bLeftDragJustEnded = true;
        bLeftDragging = false;
        bLeftDragCandidate = false;
    }

    // Right drag
    if (!bRightDragging && IsDraggingRight())
    {
        FilterDragThreshold(bRightDragCandidate, bRightDragging, bRightDragJustStarted,
            RightMouseDownPos, RightDragStartPos);
    }
    else if (GetKeyUp(VK_RBUTTON))
    {
        if (bRightDragging) bRightDragJustEnded = true;
        bRightDragging = false;
        bRightDragCandidate = false;
    }

    UpdateCurrentSnapshot();
}

FInputSystemSnapshot InputSystem::TickAndMakeSnapshot()
{
    Tick();
    return MakeSnapshot();
}

FInputSystemSnapshot InputSystem::MakeSnapshot() const
{
    return CurrentSnapshot;
}

void InputSystem::RefreshSnapshot()
{
    UpdateCurrentSnapshot();
}

void InputSystem::SetUseRawMouse(bool bEnable)
{
    if (bUseRawMouse == bEnable)
    {
        return;
    }

    bUseRawMouse = bEnable;
    ResetMouseDelta();
    UpdateCurrentSnapshot();
}

void InputSystem::AddRawMouseDelta(int DeltaX, int DeltaY)
{
    RawMouseDeltaAccumX += DeltaX;
    RawMouseDeltaAccumY += DeltaY;
}

void InputSystem::ResetTransientState()
{
    bLeftDragJustStarted = false;
    bRightDragJustStarted = false;
    bLeftDragJustEnded = false;
    bRightDragJustEnded = false;
    ResetDragState();
    ResetMouseDelta();
    ResetWheelDelta();
    UpdateCurrentSnapshot();
}

void InputSystem::ResetAllKeyStates()
{
    for (int VK = 0; VK < 256; ++VK)
    {
        CurrentStates[VK] = false;
        PrevStates[VK] = false;
    }
    UpdateCurrentSnapshot();
}

void InputSystem::ResetGamepadStates()
{
    for (int32 PadIndex = 0; PadIndex < FInputSystemSnapshot::MaxGamepads; ++PadIndex)
    {
        CurrentGamepads[PadIndex] = FGamepadSnapshot{};
        PrevGamepads[PadIndex] = FGamepadSnapshot{};
    }
    UpdateCurrentSnapshot();
}

void InputSystem::ResetMouseDelta()
{
    GetCursorPos(&MousePos);
    PrevMousePos = MousePos;
    FrameMouseDeltaX = 0;
    FrameMouseDeltaY = 0;
    RawMouseDeltaAccumX = 0;
    RawMouseDeltaAccumY = 0;
    UpdateCurrentSnapshot();
}

void InputSystem::ResetWheelDelta()
{
    ScrollDelta = 0;
    PrevScrollDelta = 0;
    UpdateCurrentSnapshot();
}

void InputSystem::ResetCaptureStateForPIEEnd()
{
    SetUseRawMouse(false);
    ResetAllKeyStates();
    ResetGamepadStates();
    ResetTransientState();
    GuiState.bUsingMouse = false;
    GuiState.bUsingKeyboard = false;
    GuiState.bUsingTextInput = false;
    UpdateCurrentSnapshot();
}

void InputSystem::UpdateCurrentSnapshot()
{
    FInputSystemSnapshot Snapshot{};
    for (int VK = 0; VK < 256; ++VK)
    {
        Snapshot.KeyDown[VK] = CurrentStates[VK];
        Snapshot.KeyPressed[VK] = CurrentStates[VK] && !PrevStates[VK];
        Snapshot.KeyReleased[VK] = !CurrentStates[VK] && PrevStates[VK];
    }

    Snapshot.bLeftMouseDown = Snapshot.KeyDown[VK_LBUTTON];
    Snapshot.bLeftMousePressed = Snapshot.KeyPressed[VK_LBUTTON];
    Snapshot.bLeftMouseReleased = Snapshot.KeyReleased[VK_LBUTTON];
    Snapshot.bRightMouseDown = Snapshot.KeyDown[VK_RBUTTON];
    Snapshot.bRightMousePressed = Snapshot.KeyPressed[VK_RBUTTON];
    Snapshot.bRightMouseReleased = Snapshot.KeyReleased[VK_RBUTTON];
    Snapshot.bMiddleMouseDown = Snapshot.KeyDown[VK_MBUTTON];
    Snapshot.bMiddleMousePressed = Snapshot.KeyPressed[VK_MBUTTON];
    Snapshot.bMiddleMouseReleased = Snapshot.KeyReleased[VK_MBUTTON];
    Snapshot.bXButton1Down = Snapshot.KeyDown[VK_XBUTTON1];
    Snapshot.bXButton1Pressed = Snapshot.KeyPressed[VK_XBUTTON1];
    Snapshot.bXButton1Released = Snapshot.KeyReleased[VK_XBUTTON1];
    Snapshot.bXButton2Down = Snapshot.KeyDown[VK_XBUTTON2];
    Snapshot.bXButton2Pressed = Snapshot.KeyPressed[VK_XBUTTON2];
    Snapshot.bXButton2Released = Snapshot.KeyReleased[VK_XBUTTON2];

    Snapshot.MousePos = MousePos;
    Snapshot.MouseDeltaX = FrameMouseDeltaX;
    Snapshot.MouseDeltaY = FrameMouseDeltaY;
    Snapshot.ScrollDelta = PrevScrollDelta;

    Snapshot.bLeftDragStarted = bLeftDragJustStarted;
    Snapshot.bLeftDragging = bLeftDragging;
    Snapshot.bLeftDragEnded = bLeftDragJustEnded;
    Snapshot.LeftDragVector = GetLeftDragVector();

    Snapshot.bRightDragStarted = bRightDragJustStarted;
    Snapshot.bRightDragging = bRightDragging;
    Snapshot.bRightDragEnded = bRightDragJustEnded;
    Snapshot.RightDragVector = GetRightDragVector();

    Snapshot.bUsingRawMouse = bUseRawMouse;
    Snapshot.bGuiUsingMouse = GuiState.bUsingMouse;
    Snapshot.bGuiUsingKeyboard = GuiState.bUsingKeyboard;
    Snapshot.bGuiUsingTextInput = GuiState.bUsingTextInput;
    Snapshot.bWindowFocused = bWindowFocused;

    for (int32 PadIndex = 0; PadIndex < FInputSystemSnapshot::MaxGamepads; ++PadIndex)
    {
        const FGamepadSnapshot& CurrentPad = CurrentGamepads[PadIndex];
        const FGamepadSnapshot& PrevPad = PrevGamepads[PadIndex];
        FGamepadSnapshot& OutPad = Snapshot.Gamepads[PadIndex];

        OutPad.bConnected = CurrentPad.bConnected;
        for (int32 AxisIndex = 0; AxisIndex < FGamepadSnapshot::MaxAxes; ++AxisIndex)
        {
            OutPad.Axes[AxisIndex] = CurrentPad.Axes[AxisIndex];
        }
        for (int32 ButtonIndex = 0; ButtonIndex < FGamepadSnapshot::MaxButtons; ++ButtonIndex)
        {
            OutPad.ButtonDown[ButtonIndex] = CurrentPad.ButtonDown[ButtonIndex];
            OutPad.ButtonPressed[ButtonIndex] = CurrentPad.ButtonDown[ButtonIndex] && !PrevPad.ButtonDown[ButtonIndex];
            OutPad.ButtonReleased[ButtonIndex] = !CurrentPad.ButtonDown[ButtonIndex] && PrevPad.ButtonDown[ButtonIndex];
        }
    }

    CurrentSnapshot = Snapshot;
}

bool InputSystem::IsGamepadConnected(int32 GamepadIndex) const
{
    if (GamepadIndex < 0 || GamepadIndex >= FInputSystemSnapshot::MaxGamepads)
    {
        return false;
    }
    return CurrentGamepads[GamepadIndex].bConnected;
}

bool InputSystem::GetGamepadButton(EGamepadButton Button, int32 GamepadIndex) const
{
    if (GamepadIndex < 0 || GamepadIndex >= FInputSystemSnapshot::MaxGamepads)
    {
        return false;
    }
    return CurrentGamepads[GamepadIndex].IsButtonDown(Button);
}

bool InputSystem::GetGamepadButtonDown(EGamepadButton Button, int32 GamepadIndex) const
{
    if (GamepadIndex < 0 || GamepadIndex >= FInputSystemSnapshot::MaxGamepads)
    {
        return false;
    }
    return CurrentGamepads[GamepadIndex].IsButtonDown(Button) &&
        !PrevGamepads[GamepadIndex].IsButtonDown(Button);
}

bool InputSystem::GetGamepadButtonUp(EGamepadButton Button, int32 GamepadIndex) const
{
    if (GamepadIndex < 0 || GamepadIndex >= FInputSystemSnapshot::MaxGamepads)
    {
        return false;
    }
    return !CurrentGamepads[GamepadIndex].IsButtonDown(Button) &&
        PrevGamepads[GamepadIndex].IsButtonDown(Button);
}

float InputSystem::GetGamepadAxis(EGamepadAxis Axis, int32 GamepadIndex) const
{
    if (GamepadIndex < 0 || GamepadIndex >= FInputSystemSnapshot::MaxGamepads)
    {
        return 0.0f;
    }
    return CurrentGamepads[GamepadIndex].GetAxis(Axis);
}

void InputSystem::PollGamepads()
{
    for (DWORD PadIndex = 0; PadIndex < static_cast<DWORD>(FInputSystemSnapshot::MaxGamepads); ++PadIndex)
    {
        FGamepadSnapshot NextPad{};

        XINPUT_STATE State{};
        const DWORD Result = XInputGetState(PadIndex, &State);
        if (Result != ERROR_SUCCESS)
        {
            CurrentGamepads[PadIndex] = NextPad;
            continue;
        }

        const XINPUT_GAMEPAD& Gamepad = State.Gamepad;
        NextPad.bConnected = true;

        SetButton(NextPad, EGamepadButton::A, (Gamepad.wButtons & XINPUT_GAMEPAD_A) != 0);
        SetButton(NextPad, EGamepadButton::B, (Gamepad.wButtons & XINPUT_GAMEPAD_B) != 0);
        SetButton(NextPad, EGamepadButton::X, (Gamepad.wButtons & XINPUT_GAMEPAD_X) != 0);
        SetButton(NextPad, EGamepadButton::Y, (Gamepad.wButtons & XINPUT_GAMEPAD_Y) != 0);
        SetButton(NextPad, EGamepadButton::LeftShoulder, (Gamepad.wButtons & XINPUT_GAMEPAD_LEFT_SHOULDER) != 0);
        SetButton(NextPad, EGamepadButton::RightShoulder, (Gamepad.wButtons & XINPUT_GAMEPAD_RIGHT_SHOULDER) != 0);
        SetButton(NextPad, EGamepadButton::Back, (Gamepad.wButtons & XINPUT_GAMEPAD_BACK) != 0);
        SetButton(NextPad, EGamepadButton::Start, (Gamepad.wButtons & XINPUT_GAMEPAD_START) != 0);
        SetButton(NextPad, EGamepadButton::LeftThumb, (Gamepad.wButtons & XINPUT_GAMEPAD_LEFT_THUMB) != 0);
        SetButton(NextPad, EGamepadButton::RightThumb, (Gamepad.wButtons & XINPUT_GAMEPAD_RIGHT_THUMB) != 0);
        SetButton(NextPad, EGamepadButton::DPadUp, (Gamepad.wButtons & XINPUT_GAMEPAD_DPAD_UP) != 0);
        SetButton(NextPad, EGamepadButton::DPadDown, (Gamepad.wButtons & XINPUT_GAMEPAD_DPAD_DOWN) != 0);
        SetButton(NextPad, EGamepadButton::DPadLeft, (Gamepad.wButtons & XINPUT_GAMEPAD_DPAD_LEFT) != 0);
        SetButton(NextPad, EGamepadButton::DPadRight, (Gamepad.wButtons & XINPUT_GAMEPAD_DPAD_RIGHT) != 0);

        const float LeftTrigger = NormalizeTrigger(Gamepad.bLeftTrigger);
        const float RightTrigger = NormalizeTrigger(Gamepad.bRightTrigger);
        SetAxis(NextPad, EGamepadAxis::LeftX, NormalizeThumbAxis(Gamepad.sThumbLX));
        SetAxis(NextPad, EGamepadAxis::LeftY, NormalizeThumbAxis(Gamepad.sThumbLY));
        SetAxis(NextPad, EGamepadAxis::RightX, NormalizeThumbAxis(Gamepad.sThumbRX));
        SetAxis(NextPad, EGamepadAxis::RightY, NormalizeThumbAxis(Gamepad.sThumbRY));
        SetAxis(NextPad, EGamepadAxis::LeftTrigger, LeftTrigger);
        SetAxis(NextPad, EGamepadAxis::RightTrigger, RightTrigger);

        const FGamepadSnapshot& PrevPad = PrevGamepads[PadIndex];
        SetButton(NextPad, EGamepadButton::LeftTrigger,
            EvaluateTriggerButton(LeftTrigger, PrevPad.IsButtonDown(EGamepadButton::LeftTrigger)));
        SetButton(NextPad, EGamepadButton::RightTrigger,
            EvaluateTriggerButton(RightTrigger, PrevPad.IsButtonDown(EGamepadButton::RightTrigger)));

        CurrentGamepads[PadIndex] = NextPad;
    }
}

void InputSystem::ResetDragState()
{
    bLeftDragCandidate = false;
    bRightDragCandidate = false;
    bLeftDragging = false;
    bRightDragging = false;
    bLeftDragJustStarted = false;
    bRightDragJustStarted = false;
    bLeftDragJustEnded = false;
    bRightDragJustEnded = false;
    LeftDragStartPos = MousePos;
    LeftMouseDownPos = MousePos;
    RightDragStartPos = MousePos;
    RightMouseDownPos = MousePos;
}

void InputSystem::FilterDragThreshold(
    bool& bCandidate, bool& bDragging, bool& bJustStarted,
    const POINT& MouseDownPos, POINT& DragStartPos)
{
    if (bCandidate && !bDragging)
    {
        int DX = MousePos.x - MouseDownPos.x;
        int DY = MousePos.y - MouseDownPos.y;
        int DistSq = DX * DX + DY * DY;

        if (DistSq >= DRAG_THRESHOLD * DRAG_THRESHOLD)
        {
            bJustStarted = true;
            bDragging = true;
            DragStartPos = MouseDownPos;
        }
    }
}

POINT InputSystem::GetLeftDragVector() const
{
    POINT V;
    V.x = MousePos.x - LeftDragStartPos.x;
    V.y = MousePos.y - LeftDragStartPos.y;
    return V;
}

POINT InputSystem::GetRightDragVector() const
{
    POINT V;
    V.x = MousePos.x - RightDragStartPos.x;
    V.y = MousePos.y - RightDragStartPos.y;
    return V;
}

float InputSystem::GetLeftDragDistance() const
{
    POINT V = GetLeftDragVector();
    return std::sqrt((float)(V.x * V.x + V.y * V.y));
}

float InputSystem::GetRightDragDistance() const
{
    POINT V = GetRightDragVector();
    return std::sqrt((float)(V.x * V.x + V.y * V.y));
}
