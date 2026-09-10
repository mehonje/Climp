package main

import "vendor:windows/GameInput"
import "ansi"
import "term"
import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"
import rl "vendor:raylib"

Bar_Style :: enum{
	THIN,
	THICK,
}

main :: proc() {
  args: [dynamic]string
  defer delete(args)
  for arg in os.args {
    append(&args, arg)
  }

	if len(args) <= 1 {
		return
	}

  shuffle := false
	bar_style := Bar_Style.THICK

  {
    i := 0
    for i < len(args) {
      if strings.has_prefix(args[i], "-") {
        switch args[i] {
          case "-shuffle":
            shuffle = true
					case "-thin":
						bar_style = Bar_Style.THIN
        }
        ordered_remove(&args, i)
        i -= 1
      }
      i += 1
    }
  }

	binary_path, err := os.get_executable_path(context.allocator)
	if err != nil {
		fmt.eprintfln("Failed to get binary location: %w", err)
		return
	}

	working_directory := filepath.dir(binary_path)

	delete(binary_path)

  queue: [dynamic]string
  defer {
    for song in queue {
      delete(song)
    }
    delete(queue)
  }

  switch args[1] {
    case "play":
      file_ext := filepath.ext(args[2])
      switch file_ext {
        case "": // queue
          if args[2] == "queue" {
						file_path := fmt.tprintf("{}/data/queue.txt", working_directory)
            file_data, err := os.read_entire_file(file_path, context.allocator)
            if err != nil {
              fmt.eprintfln("Failed to read data/queue.txt: %w", err)
              return
            }
            defer delete(file_data)

            iter := string(file_data)
            for line in strings.split_lines_iterator(&iter) {
              cloned_line := strings.clone(line)
              append(&queue, cloned_line)
            }
          }
        case ".txt": // playlist
          file_path := fmt.tprintf("{}/data/playlists/{}", working_directory, args[2])
          file_data, err := os.read_entire_file(file_path, context.allocator)
          if err != nil {
            fmt.eprintfln("Failed to read %s: %w", file_path, err)
            return
          }
          defer delete(file_data)

          iter := string(file_data)
          for line in strings.split_lines_iterator(&iter) {
            song_path := fmt.tprintf("{}/data/songs/{}", working_directory, line)
            cloned_line := strings.clone(song_path)
            append(&queue, cloned_line)
          }
        case: // audio file
          file_path := fmt.tprintf("{}/data/songs/{}", working_directory, args[2])
          cloned := strings.clone(file_path)
          append(&queue, cloned)
      }
    case "add":
      add_lines: [dynamic]string
      defer {
        for song in queue {
          delete(song)
        }
        delete(queue)
      }

      file_ext := filepath.ext(args[3])

      switch file_ext {
        case "": // queue
          if args[3] == "queue" {
            fmt.printfln("Cannot add queue to %s", args[2])
          } else {
            fmt.printfln("Unknown file \"%s\"", args[3])
          }
        case ".txt": // playlist
          file_path := fmt.tprintf("{}/data/playlists/{}", working_directory, args[3])
          file_data, err := os.read_entire_file(file_path, context.allocator)
          if err != nil {
            fmt.eprintfln("Failed to read %s: %w", file_path, err)
            return
          }
          defer delete(file_data)

          iter := string(file_data)
          for line in strings.split_lines_iterator(&iter) {
            cloned_line := strings.clone(line)
            append(&add_lines, cloned_line)
          }
        case: // audio file
          append(&add_lines, args[3])
      }
      
      file_ext = filepath.ext(args[2])

      file_path: string

      switch file_ext {
        case "": // queue
          if args[2] == "queue" {
            file_path = "data/queue.txt"
          } else {
            fmt.printfln("Unknown file \"%s\"", args[2])
          }
        case ".txt": // playlist
          file_path = fmt.tprintf("{}/data/playlists/{}", working_directory, args[2])
        case: // audio file
          fmt.printfln("Cannot add to an audio file")
      }

      handle, err := os.open(file_path, os.O_RDWR | os.O_APPEND | os.O_CREATE)
      if err != os.ERROR_NONE {
          fmt.eprintln("Error opening file: ", err)
      }
      defer os.close(handle)

      builder := strings.builder_make()
      defer strings.builder_destroy(&builder)
      for line in add_lines {
        strings.write_string(&builder, line)
        strings.write_byte(&builder, '\n')
      }
      str := strings.to_string(builder)
      fmt.println("---", str, "---")
      
      _, write_err := os.write(handle, transmute([]u8)str)
      if write_err != os.ERROR_NONE {
        fmt.eprintln("Error writing to file: ", write_err)
        return
      }
  }

  free_all(context.allocator)
  free_all(context.temp_allocator)

  if len(queue) > 0 { // init music player
    term.enable_utf8()

    cooked_state, raw_ok := term.enable_raw_mode()
    if !raw_ok {
        fmt.eprintln("Error: Failed to enter raw mode")
        return
    }
    defer term.disable_raw_mode(cooked_state)

	  fmt.print(ansi.HIDE_CURSOR) // hide cursor
    defer fmt.print(ansi.SHOW_CURSOR) // show cursor


    quit := false
    song_idx := 0

    if shuffle {
      rand.shuffle(queue[:])
    }

    rl.SetTraceLogLevel(.NONE)

    rl.InitAudioDevice()
    defer rl.CloseAudioDevice()

    paused := false
		volume := 100

    for song_idx < len(queue) && !quit {
      str := strings.clone_to_cstring(queue[song_idx], context.temp_allocator)
  
      music := rl.LoadMusicStream(str)
  
      song_length := rl.GetMusicTimeLength(music)

      if rl.IsMusicValid(music) {
        music.looping = false 

        paused = false

        filename := filepath.short_stem(queue[song_idx])
        allocated_filename: bool
        filename, allocated_filename = strings.replace_all(filename, "--", " ")
        split := strings.split(filename, "__")
        song_name := strings.clone(split[0])
        song_artist := strings.clone(split[1])
        delete(split)

				window_name := fmt.tprintf("{} - {} - climp.exe", song_name, song_artist)
				term.set_window_name(window_name)

        rl.PlayMusicStream(music)

        song_loop: for !quit {
          rl.UpdateMusicStream(music)

          elapsed := rl.GetMusicTimePlayed(music)

          if !rl.IsMusicStreamPlaying(music) && !paused {
            break
          }

          if !paused && elapsed > song_length {
            break
          }

					volume_changed := false

					char: u8
					pressed: bool

					for char, pressed = term.poll_key(); pressed; char, pressed = term.poll_key() {
        	  switch char {
        	    case 'q':
        	      quit = true
        	    case 'H':
        	      song_idx -= 2
        	      if song_idx < -1 { // incremented to 0 later, so it is safe
        	        song_idx = -1
        	      }
        	      break song_loop
        	    case 'L':
        	      break song_loop
							case 'h':
								rl.SeekMusicStream(music, max(elapsed - 5.0, 0.0))
							case 'l':
								rl.SeekMusicStream(music, min(elapsed + 5.0, song_length)) 
					  	case 'j':
					  		volume_changed = true
					  		volume -= 1
					  		if volume < 0 {
					  			volume = 0
					  		}
					  	case 'k':
					  		volume_changed = true
					  		volume += 1
					  		if volume > 100 {
					  			volume = 100
					  		}
        	    case ' ':
        	      paused = !paused
        	      if paused {
        	        rl.PauseMusicStream(music)
        	      } else {
        	        rl.ResumeMusicStream(music)
        	      }
        	  }
					}

					if volume_changed {
						rl.SetMusicVolume(music, f32(volume) / 100.0)
					}

          print_ui(elapsed, song_length, song_name, song_artist, paused, volume, bar_style)

          time.sleep(16 * time.Millisecond)
        }

        if allocated_filename {
          delete(filename)
        }
        delete(song_name)
        delete(song_artist)
      }

      rl.UnloadMusicStream(music)

      free_all(context.temp_allocator)

      song_idx += 1
    }
  }
}

print_ui :: proc(elapsed, length: f32, name, artist: string, paused: bool, volume: int, bar_style: Bar_Style) {
  elapsed_minutes := i32(elapsed) / 60
  elapsed_seconds := i32(elapsed) % 60
  
  length_minutes := i32(length) / 60
  length_seconds := i32(length) % 60

  builder := strings.builder_make()
  defer strings.builder_destroy(&builder)

  strings.write_string(&builder, "\033[H\033[2J")

  str := fmt.tprintf("%02d:%02d ", elapsed_minutes, elapsed_seconds)
  strings.write_string(&builder, str)

  make_progress_bar(&builder, elapsed, length, 20, bar_style)

  str = fmt.tprintf(" %02d:%02d", length_minutes, length_seconds)
  strings.write_string(&builder, str)

  str = fmt.tprintf("\r\n{} - {}", name, artist)
  strings.write_string(&builder, str)

	strings.write_string(&builder, "\nVolume ")

  make_progress_bar(&builder, f32(volume) / 100.0, 1.0, 20, bar_style)

  str = fmt.tprintf(" %d%%", volume)
	strings.write_string(&builder, str)

  if paused {
    strings.write_string(&builder, "\r\nPaused")
  }

  fmt.print(strings.to_string(builder))
}

make_progress_bar :: proc(builder: ^strings.Builder, elapsed, length: f32, width: int, style: Bar_Style) {
	if width <= 0 {
		return
	}
	progress: f32 = 0.0
	if length != 0 {
		progress = math.floor(elapsed) / math.floor(length)
	}

	progress = clamp(progress, 0.0, 1.0)

	chars: []rune

	total_portions := int(progress * f32(width * 8))
	full_portions: int
	partial_portions: int

	switch style {
		case .THICK:
		  chars = []rune{'█', '▉', '▊', '▋', '▌', '▍', '▎', '▏'}
		
			total_portions = int(progress * f32(width * 8))
		
		  full_portions = total_portions / 8
		  partial_portions = total_portions % 8
		case .THIN:
		  chars = []rune{'━', '╸'}
		
			total_portions = int(progress * f32(width * 2))
		
		  full_portions = total_portions / 2
		  partial_portions = total_portions % 2
	}

	for i in 0..<full_portions {
		strings.write_rune(builder, '█')
	}

  if full_portions < width && partial_portions > 0 {
		strings.write_rune(builder, chars[8 - partial_portions])
  }

  used := full_portions
  if partial_portions > 0 {
		used += 1
  }

  for i in used..<width {
		strings.write_rune(builder, ' ')
  }

}

