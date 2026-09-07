package term

import "core:fmt"
import "core:os"

import "core:sys/posix"
import "core:sys/windows"

foreign import kernel32 "system:kernel32.lib"
@(default_calling_convention="system")
foreign kernel32 {
	SetConsoleTitleW :: proc(lpConsoleTitle: windows.wstring) -> windows.BOOL ---
}

when ODIN_OS == .Windows {
  Terminal_State :: windows.DWORD
} else {
  Terminal_State :: posix.termios
}

enable_raw_mode :: proc() -> (state: Terminal_State, success: bool) {
    // ---- WINDOWS IMPLEMENTATION ----
    when ODIN_OS == .Windows {
        handle := windows.GetStdHandle(windows.STD_INPUT_HANDLE)
        if handle == windows.INVALID_HANDLE_VALUE do return 0, false
        if !bool(windows.GetConsoleMode(handle, &state)) do return 0, false

        raw := state
        raw &~= windows.ENABLE_LINE_INPUT
        raw &~= windows.ENABLE_ECHO_INPUT
        raw &~= windows.ENABLE_PROCESSED_INPUT

        if !bool(windows.SetConsoleMode(handle, raw)) do return 0, false
        return state, true

    // ---- POSIX (LINUX / MACOS) IMPLEMENTATION ----
    } else {
        // File descriptor 0 is standard input
        if posix.tcgetattr(0, &state) != 0 do return state, false

        raw := state
        raw.c_lflag &~= { .ECHO, .ICANON, .ISIG }
        
        if posix.tcsetattr(0, .TCSANOW, &raw) != 0 do return state, false
        return state, true
    }
}

disable_raw_mode :: proc(original: Terminal_State) {
    when ODIN_OS == .Windows {
        handle := windows.GetStdHandle(windows.STD_INPUT_HANDLE)
        windows.SetConsoleMode(handle, original)
    } else {
        posix.tcsetattr(0, .TCSANOW, &original)
    }
}

poll_key :: proc() -> (key: u8, pressed: bool) {
  when ODIN_OS == .Windows {
    handle := windows.GetStdHandle(windows.STD_INPUT_HANDLE)
    num_events: windows.DWORD = 0
    
    // Peek at the buffer size to ensure we don't stall the loop
    if !bool(windows.GetNumberOfConsoleInputEvents(handle, &num_events)) || num_events == 0 {
        return 0, false
    }
    
    event_buffer: windows.INPUT_RECORD
    events_read: windows.DWORD = 0
    
    // Extract a singular event package
    if !bool(windows.ReadConsoleInputW(handle, &event_buffer, 1, &events_read)) || events_read == 0 {
        return 0, false
    }
    
    // 1 represents a KEY_EVENT structure type in the Win32 API
    if event_buffer.EventType == windows.Event_Type.KEY_EVENT { 
        key_record := event_buffer.Event.KeyEvent
        
        // Only capture down-presses (bKeyDown = TRUE) and filter out key-release variants
        if bool(key_record.bKeyDown) {
            return u8(key_record.uChar.AsciiChar), true
        }
    }
    return 0, false
    
  } else {
    buf: u8
    bytes_read, err := os.read(os.stdin, buf[:])
    if err == 0 && bytes_read > 0 {
        return buf, true
    }
    return 0, false
  }
}

enable_utf8 :: proc() {
  when ODIN_OS == .Windows {
    enable_utf8_windows()
  }
}

enable_utf8_windows :: proc() {
  CP_UTF8 :: windows.CODEPAGE(65001)
	if !windows.SetConsoleOutputCP(CP_UTF8) {
		fmt.printfln("Failed to set console output CP to UTF-8. Error code: %v", windows.GetLastError())
		os.exit(1)
	}

	if !windows.SetConsoleCP(CP_UTF8) {
		fmt.printfln("Failed to set console input CP to UTF-8. Error code: %v", windows.GetLastError())
		os.exit(1)
	}
}

set_window_name :: proc(name: string) {
	when ODIN_OS == .Windows {
		set_window_name_windows(name)
	}
}

set_window_name_windows :: proc(name: string) {
	name_utf16 := windows.utf8_to_utf16(name)

	SetConsoleTitleW(cast(windows.wstring)raw_data(name_utf16))
}
