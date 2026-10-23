package main

import "ansi"
import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"
import simterm "simpleterm/terminal"
import keys "simpleterm/terminal/keys"
import rl "vendor:raylib"

Config :: struct {
	splitter:  string,
	song_path: string,
}

Bar_Style :: enum {
	THIN,
	THICK,
}

main :: proc() {
	defer fmt.print("\n") // add newline so terminal prompt begins on new line

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
	defer delete(binary_path)

	working_directory := filepath.dir(binary_path)

	queue: [dynamic]string
	defer {
		for song in queue {
			delete(song)
		}
		delete(queue)
	}

	config: Config
	{
		config_path := fmt.tprintf("{}/data/config.json", working_directory)
		config_bytes, read_err := os.read_entire_file(config_path, context.allocator)
		if read_err != nil {
			fmt.eprintfln("Failed to read \"%s\": %w", config_path, read_err)
			return
		}
		defer delete(config_bytes)


		json_err := json.unmarshal(config_bytes, &config)
		if json_err != nil {
			fmt.eprintfln("Failed to parse config json: %w", json_err)
			return
		}
	}

	switch args[1] {
	case "splitter":
		if len(args) > 2 {
			config.splitter = args[2]

			file_path := fmt.tprintf("{}/data/config.json", working_directory)

			json_options := json.Marshal_Options {
				pretty = true,
			}

			json_bytes, json_err := json.marshal(config, json_options)
			if err != nil {
				fmt.eprintfln("Failed to turn config into a JSON: %w", err)
				return
			}
			defer delete(json_bytes)

			write_err := os.write_entire_file(file_path, json_bytes)
			if write_err != nil {
				fmt.eprintfln("Failed to save config to %s: %w", file_path, write_err)
				return
			}
		} else {
			fmt.printfln("Splitter: %s", config.splitter)
			return
		}
	case "song_path":
		if len(args) > 2 {
			config.song_path = args[2]

			file_path := fmt.tprintf("{}/data/config.json", working_directory)

			json_options := json.Marshal_Options {
				pretty = true,
			}

			json_bytes, json_err := json.marshal(config, json_options)
			if err != nil {
				fmt.eprintfln("Failed to turn config into a JSON: %w", err)
				return
			}
			defer delete(json_bytes)

			write_err := os.write_entire_file(file_path, json_bytes)
			if write_err != nil {
				fmt.eprintfln("Failed to save config to %s: %w", file_path, write_err)
				return
			}
		} else {
			fmt.printfln("Song path: %s", config.song_path)
			return
		}
	case "play":
		file_ext := filepath.ext(args[2])
		switch file_ext {
		case "":
			// queue
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
		case ".txt":
			// playlist
			file_path := fmt.tprintf("{}/data/playlists/{}", working_directory, args[2])
			file_data, err := os.read_entire_file(file_path, context.allocator)
			if err != nil {
				fmt.eprintfln("Failed to read %s: %w", file_path, err)
				return
			}
			defer delete(file_data)

			iter := string(file_data)
			for line in strings.split_lines_iterator(&iter) {
				song_path := fmt.tprintf("{}/{}", config.song_path, line)
				cloned_line := strings.clone(song_path)
				append(&queue, cloned_line)
			}
		case:
			// audio file
			file_path := fmt.tprintf("{}/{}", config.song_path, args[2])
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
		case "":
			// queue
			if args[3] == "queue" {
				fmt.printfln("Cannot add queue to %s", args[2])
			} else {
				fmt.printfln("Unknown file \"%s\"", args[3])
			}
		case ".txt":
			// playlist
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
		case:
			// audio file
			append(&add_lines, args[3])
		}

		file_ext = filepath.ext(args[2])

		file_path: string

		switch file_ext {
		case "":
			// queue
			if args[2] == "queue" {
				file_path = "data/queue.txt"
			} else {
				fmt.printfln("Unknown file \"%s\"", args[2])
			}
		case ".txt":
			// playlist
			file_path = fmt.tprintf("{}/data/playlists/{}", working_directory, args[2])
		case:
			// audio file
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

	if len(queue) > 0 { 	// init music player
		cooked_state, handle, err := simterm.enable_raw_state(true)
		if err != nil {
			fmt.eprintln("Error: Failed to enter raw mode")
			return
		}
		defer simterm.disable_raw_state(&cooked_state, handle)

		fmt.print(ansi.HIDE_CURSOR) // hide cursor
		defer fmt.print(ansi.SHOW_CURSOR) // show cursor

		buf := make([]u8, 64) // buffer used for user input
		defer delete(buf)

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

				split := strings.split(filename, config.splitter)


				song_name: string
				if len(split) > 0 {
					song_name = strings.clone(split[0])
				}
				song_artist: string
				if len(split) > 1 {
					song_artist = strings.clone(split[1])
				}

				delete(split)

				window_name := fmt.tprintf("{} - {} - climp.exe", song_name, song_artist)
				//simterm.set_window_name(window_name)

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

					{
						key_event, ok, err := simterm.read_key_bytes(handle, buf)

						if err != nil {
							quit = true
							break song_loop
						}

						if ok {
							switch key_event {
							case keys.Key_Event{key = 'q'}:
								quit = true
								break song_loop
							case keys.Key_Event{key = 'h', modifiers = {shift = true}}:
								song_idx -= 2
								if song_idx < -1 { 	// incremented to 0 later, so it is safe
									song_idx = -1
								}
								break song_loop
							case keys.Key_Event{key = 'l', modifiers = {shift = true}}:
								break song_loop
							case keys.Key_Event{key = 'h'}:
								rl.SeekMusicStream(music, max(elapsed - 5.0, 0.0))
							case keys.Key_Event{key = 'l'}:
								rl.SeekMusicStream(music, min(elapsed + 5.0, song_length))
							case keys.Key_Event{key = 'j'}:
								volume_changed = true
								volume -= 1
								if volume < 0 {
									volume = 0
								}
							case keys.Key_Event{key = 'k'}:
								volume_changed = true
								volume += 1
								if volume > 100 {
									volume = 100
								}
							case keys.Key_Event{key = ' '}:
								paused = !paused
								if paused {
									rl.PauseMusicStream(music)
								} else {
									rl.ResumeMusicStream(music)
								}
							}
						}
					}

					if volume_changed {
						rl.SetMusicVolume(music, f32(volume) / 100.0)
					}

					print_ui(
						elapsed,
						song_length,
						song_name,
						song_artist,
						paused,
						volume,
						bar_style,
					)

					time.sleep(16 * time.Millisecond)
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


print_ui :: proc(
	elapsed, length: f32,
	name, artist: string,
	paused: bool,
	volume: int,
	bar_style: Bar_Style,
) {
	elapsed_minutes := i32(elapsed) / 60
	elapsed_seconds := i32(elapsed) % 60

	length_minutes := i32(length) / 60
	length_seconds := i32(length) % 60

	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)

	strings.write_string(&builder, "\033[H\033[2J")

	str := fmt.tprintf("%02d:%02d ", elapsed_minutes, elapsed_seconds)
	strings.write_string(&builder, str)

	make_progress_bar(&builder, math.floor(elapsed), length, 20, bar_style)

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

make_progress_bar :: proc(
	builder: ^strings.Builder,
	elapsed, length: f32,
	width: int,
	style: Bar_Style,
) {
	if width <= 0 {
		return
	}
	progress: f32 = 0.0
	if length != 0 {
		progress = elapsed / length
	}

	progress = clamp(progress, 0.0, 1.0)

	chars: []rune
	portions: int

	switch style {
	case .THICK:
		chars = []rune{'█', '▉', '▊', '▋', '▌', '▍', '▎', '▏'}
		portions = 8
	case .THIN:
		chars = []rune{'━', '╸'}
		portions = 2
	}

	total_portions := int(progress * f32(width * portions))

	full_portions := total_portions / portions
	partial_portions := total_portions % portions

	for i in 0 ..< full_portions {
		strings.write_rune(builder, chars[0])
	}

	if full_portions < width && partial_portions > 0 {
		strings.write_rune(builder, chars[portions - partial_portions])
	}

	used := full_portions
	if partial_portions > 0 {
		used += 1
	}

	for i in used ..< width {
		strings.write_rune(builder, ' ')
	}
}
