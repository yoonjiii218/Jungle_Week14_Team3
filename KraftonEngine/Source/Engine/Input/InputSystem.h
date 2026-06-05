#pragma once
#include <windows.h>
#include "Core/Singleton.h"
#include "Core/Types/CoreTypes.h"

struct FGuiInputState
{
    bool bUsingMouse = false;
    bool bUsingKeyboard = false;
    bool bUsingTextInput = false;
};

enum class EGamepadButton : uint8
{
    A = 0,
    B,
    X,
    Y,
    LeftShoulder,
    RightShoulder,
    Back,
    Start,
    LeftThumb,
    RightThumb,
    DPadUp,
    DPadDown,
    DPadLeft,
    DPadRight,
    LeftTrigger,
    RightTrigger,
    Count,
};

enum class EGamepadAxis : uint8
{
    LeftX = 0,
    LeftY,
    RightX,
    RightY,
    LeftTrigger,
    RightTrigger,
    Count,
};

struct FGamepadSnapshot
{
    static constexpr int32 MaxButtons = static_cast<int32>(EGamepadButton::Count);
    static constexpr int32 MaxAxes = static_cast<int32>(EGamepadAxis::Count);

    bool bConnected = false;
    bool ButtonDown[MaxButtons] = {};
    bool ButtonPressed[MaxButtons] = {};
    bool ButtonReleased[MaxButtons] = {};
    float Axes[MaxAxes] = {};

    bool IsButtonDown(EGamepadButton Button) const { return ButtonDown[static_cast<int32>(Button)]; }
    bool WasButtonPressed(EGamepadButton Button) const { return ButtonPressed[static_cast<int32>(Button)]; }
    bool WasButtonReleased(EGamepadButton Button) const { return ButtonReleased[static_cast<int32>(Button)]; }
    float GetAxis(EGamepadAxis Axis) const { return Axes[static_cast<int32>(Axis)]; }
};

struct FInputSystemSnapshot
{
    bool KeyDown[256] = {};
    bool KeyPressed[256] = {};
    bool KeyReleased[256] = {};

    POINT MousePos = { 0, 0 };
    int MouseDeltaX = 0;
    int MouseDeltaY = 0;
    int ScrollDelta = 0;

    bool bLeftMouseDown = false;
    bool bLeftMousePressed = false;
    bool bLeftMouseReleased = false;
    bool bRightMouseDown = false;
    bool bRightMousePressed = false;
    bool bRightMouseReleased = false;
    bool bMiddleMouseDown = false;
    bool bMiddleMousePressed = false;
    bool bMiddleMouseReleased = false;
    bool bXButton1Down = false;
    bool bXButton1Pressed = false;
    bool bXButton1Released = false;
    bool bXButton2Down = false;
    bool bXButton2Pressed = false;
    bool bXButton2Released = false;

    bool bLeftDragStarted = false;
    bool bLeftDragging = false;
    bool bLeftDragEnded = false;
    POINT LeftDragVector = { 0, 0 };

    bool bRightDragStarted = false;
    bool bRightDragging = false;
    bool bRightDragEnded = false;
    POINT RightDragVector = { 0, 0 };

    bool bUsingRawMouse = false;
    bool bGuiUsingMouse = false;
    bool bGuiUsingKeyboard = false;
    bool bGuiUsingTextInput = false;
    bool bWindowFocused = true;

    static constexpr int32 MaxGamepads = 4;
    FGamepadSnapshot Gamepads[MaxGamepads] = {};

    bool IsDown(int VK) const { return KeyDown[VK]; }
    bool WasPressed(int VK) const { return KeyPressed[VK]; }
    bool WasReleased(int VK) const { return KeyReleased[VK]; }
};

class InputSystem : public TSingleton<InputSystem>
{
	friend class TSingleton<InputSystem>;

public:
    void Tick();
    FInputSystemSnapshot TickAndMakeSnapshot();
    FInputSystemSnapshot MakeSnapshot() const;
    void RefreshSnapshot();
    void SetUseRawMouse(bool bEnable);
    bool IsUsingRawMouse() const { return bUseRawMouse; }
    void AddRawMouseDelta(int DeltaX, int DeltaY);
    void ResetTransientState();
    void ResetAllKeyStates();
    void ResetMouseDelta();
    void ResetWheelDelta();
    void ResetCaptureStateForPIEEnd();
    bool IsWindowFocused() const { return bWindowFocused; }

    // Keyboard
    bool GetKeyDown(int VK) const { return CurrentStates[VK] && !PrevStates[VK]; }
    bool GetKey(int VK) const { return CurrentStates[VK]; }
    bool GetKeyUp(int VK) const { return !CurrentStates[VK] && PrevStates[VK]; }

    // Gamepad
    bool IsGamepadConnected(int32 GamepadIndex = 0) const;
    bool GetGamepadButton(EGamepadButton Button, int32 GamepadIndex = 0) const;
    bool GetGamepadButtonDown(EGamepadButton Button, int32 GamepadIndex = 0) const;
    bool GetGamepadButtonUp(EGamepadButton Button, int32 GamepadIndex = 0) const;
    float GetGamepadAxis(EGamepadAxis Axis, int32 GamepadIndex = 0) const;

    // Mouse position
    POINT GetMousePos() const { return MousePos; }
    POINT GetMouseClientPos() const
    {
        POINT ClientPos = MousePos;
        if (OwnerHWnd)
        {
            ScreenToClient(OwnerHWnd, &ClientPos);
        }
        return ClientPos;
    }
    int MouseDeltaX() const { return FrameMouseDeltaX; }
    int MouseDeltaY() const { return FrameMouseDeltaY; }
    bool MouseMoved() const { return MouseDeltaX() != 0 || MouseDeltaY() != 0; }

    // Left drag
    bool IsDraggingLeft() const { return GetKey(VK_LBUTTON) && MouseMoved(); }
    bool GetLeftDragStart() const { return bLeftDragJustStarted; }
    bool GetLeftDragging() const { return bLeftDragging; }
    bool GetLeftDragEnd() const { return bLeftDragJustEnded; }
    POINT GetLeftDragVector() const;
    float GetLeftDragDistance() const;

    // Right drag
    bool IsDraggingRight() const { return GetKey(VK_RBUTTON) && MouseMoved(); }
    bool GetRightDragStart() const { return bRightDragJustStarted; }
    bool GetRightDragging() const { return bRightDragging; }
    bool GetRightDragEnd() const { return bRightDragJustEnded; }
    POINT GetRightDragVector() const;
    float GetRightDragDistance() const;

    // Scrolling
    void AddScrollDelta(int Delta) { ScrollDelta += Delta; }
    int GetScrollDelta() const { return PrevScrollDelta; }
    bool ScrolledUp() const { return PrevScrollDelta > 0; }
    bool ScrolledDown() const { return PrevScrollDelta < 0; }
    float GetScrollNotches() const { return PrevScrollDelta / (float)WHEEL_DELTA; }

    // Window focus
    void SetOwnerWindow(HWND InHWnd) { OwnerHWnd = InHWnd; }

    // GUI state
    FGuiInputState& GetGuiInputState() { return GuiState; }
    const FGuiInputState& GetGuiInputState() const { return GuiState; }
    void SetGuiMouseCapture(bool bCapture) { GuiState.bUsingMouse = bCapture; }
    void SetGuiKeyboardCapture(bool bCapture) { GuiState.bUsingKeyboard = bCapture; }
    void SetGuiTextInputCapture(bool bCapture) { GuiState.bUsingTextInput = bCapture; }
    bool IsGuiUsingMouse() const { return GuiState.bUsingMouse; }
    bool IsGuiUsingKeyboard() const { return GuiState.bUsingKeyboard; }
    bool IsGuiUsingTextInput() const { return GuiState.bUsingTextInput; }

private:
    bool CurrentStates[256] = { false };
    bool PrevStates[256] = { false };

    FGamepadSnapshot CurrentGamepads[FInputSystemSnapshot::MaxGamepads] = {};
    FGamepadSnapshot PrevGamepads[FInputSystemSnapshot::MaxGamepads] = {};

    // Mouse members
    POINT MousePos = { 0, 0 };
    POINT PrevMousePos = { 0, 0 };
    int FrameMouseDeltaX = 0;
    int FrameMouseDeltaY = 0;
    int RawMouseDeltaAccumX = 0;
    int RawMouseDeltaAccumY = 0;
    bool bUseRawMouse = false;

    bool bLeftDragCandidate = false;
    bool bRightDragCandidate = false;
    bool bLeftDragging = false;
    bool bRightDragging = false;

    bool bLeftDragJustStarted = false;
    bool bRightDragJustStarted = false;
    bool bLeftDragJustEnded = false;
    bool bRightDragJustEnded = false;

    // Drag origin
    POINT LeftDragStartPos = { 0, 0 };
    POINT LeftMouseDownPos = { 0, 0 };
    POINT RightDragStartPos = { 0, 0 };
    POINT RightMouseDownPos = { 0, 0 };

    // Scrolling
    int ScrollDelta = 0;
    int PrevScrollDelta = 0;

    // Window handle for focus check
    HWND OwnerHWnd = nullptr;

    // GUI InputState
    FGuiInputState GuiState{};
    FInputSystemSnapshot CurrentSnapshot{};
    bool bWindowFocused = true;

    static constexpr int DRAG_THRESHOLD = 5;

    // Internal drag threshold helper — unified Left/Right logic
    void FilterDragThreshold(
        bool& bCandidate, bool& bDragging, bool& bJustStarted,
        const POINT& MouseDownPos, POINT& DragStartPos);
    void UpdateCurrentSnapshot();
    void ResetDragState();
    void PollGamepads();
    void ResetGamepadStates();
};
