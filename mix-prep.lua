-- Import and organize audio/MIDI tracks using an existing template

------------------------------------------------------------
-- CONFIGURATION
------------------------------------------------------------

local CONFIG = {
  volume_db = -12,
  clean_track_names = true,

  routes = {
    "KICK",
    "SNARE",
    "TOMS",
    "OH",
    "ROOMS",
    "BASS",
    "MAIN GTRS",
    "LEAD GTRS",
    "CLEAN GTRS",
    "MAIN VOCALS",
    "SCREAM VOCALS",
    "BG VOCALS",
    "HARM VOCALS",
    "GROUP VOCALS",
    "MIDI",
    "XTRA"
  },

  keywords = {
    fx = {
      "fx"
    },

    kick = {
      "kick",
      "kickin",
      "kickout",
      "kick trigger",
      "kick sample"
    },

    snare = {
      "snare",
      "sn",
      "snr",
      "snare top",
      "snare bottom",
      "snare btm",
      "snr top",
      "snr btm"
    },

    toms = {
      "tom",
      "toms",
      "rack tom",
      "floor tom"
    },

    cymbals = {
      "oh",
      "overhead",
      "overheads",
      "hh",
      "hat",
      "hats",
      "hi hat",
      "hi hats",
      "hihat",
      "hihats",
      "open hat",
      "closed hat",
      "ride",
      "china",
      "crash",
      "splash",
      "cymbal",
      "cymbals",
      "bell",
      "stack"
    },

    rooms = {
      "room",
      "rooms",
      "corner",
      "corners"
    },

    bass = {
      "bass",
      "sub"
    },

    guitar = {
      "gtr",
      "guitar"
    },

    lead_guitar = {
      "lead",
      "leadgtr",
      "gtrlead"
    },

    clean_guitar = {
      "clean",
      "cleangtr",
      "gtrclean",
      "acoustic",
      "nylon",
      "classical",
      "ac gtr",
      "ac guitar"
    },

    main_guitar = {
      "rhythm",
      "rhy",
      "rhy gtr",
      "rh gtr"
    },

    scream_vocals = {
      "scream",
      "growl",
      "harsh"
    },

    bg_vocals = {
      "bg",
      "bgv",
      "bv",
      "backing",
      "backup",
      "back up",
      "background",
      "bg vocal",
      "bg vocals",
      "backup vocal",
      "backup vocals",
      "vox backup"
    },

    harm_vocals = {
      "harm",
      "harmony",
      "harmonies"
    },

    group_vocals = {
      "group",
      "gang",
      "choir"
    },

    main_vocals = {
      "vocal",
      "vocals",
      "vox",
      "voice"
    }
  }
}

local TARGET_VOLUME =
  10 ^ (CONFIG.volume_db / 20)

------------------------------------------------------------
-- SAFE EXECUTION
------------------------------------------------------------

local undo_is_open = false
local ui_is_locked = false

local function begin_undo()
  reaper.Undo_BeginBlock()
  undo_is_open = true
end

local function end_undo(description)
  if undo_is_open then
    reaper.Undo_EndBlock(description, -1)
    undo_is_open = false
  end
end

local function lock_ui()
  if not ui_is_locked then
    reaper.PreventUIRefresh(1)
    ui_is_locked = true
  end
end

local function unlock_ui()
  if ui_is_locked then
    reaper.PreventUIRefresh(-1)
    ui_is_locked = false
  end
end

------------------------------------------------------------
-- NAME UTILITIES
------------------------------------------------------------

local function normalize(text)
  text = text or ""

  -- Lead1     -> Lead 1
  -- OverheadL -> Overhead L
  -- RoomR     -> Room R
  -- KickIn    -> Kick In
  text = text:gsub("(%l)(%u)", "%1 %2")
  text = text:gsub("(%a)(%d)", "%1 %2")
  text = text:gsub("(%d)(%a)", "%1 %2")

  return " "
    .. text:lower():gsub("[^%w]+", " ")
    .. " "
end

local function contains(text, phrase)
  return text:find(
    " " .. phrase .. " ",
    1,
    true
  ) ~= nil
end

local function matches_any(text, words)
  for _, word in ipairs(words) do
    if contains(text, word) then
      return true
    end
  end

  return false
end

local function folder_key(name)
  return (name or "")
    :gsub("Σ", "")
    :gsub("∑", "")
    :match("^%s*(.-)%s*$")
    :upper()
end

local function get_track_name(track)
  local _, name =
    reaper.GetSetMediaTrackInfo_String(
      track,
      "P_NAME",
      "",
      false
    )

  return name
end

local function get_take_name(track)
  local item = reaper.GetTrackMediaItem(track, 0)
  local take = item and reaper.GetActiveTake(item)

  if take then
    return reaper.GetTakeName(take)
  end

  return ""
end

local function track_label(track)
  return get_track_name(track)
    .. " "
    .. get_take_name(track)
end

------------------------------------------------------------
-- MIDI UTILITIES
------------------------------------------------------------

local function is_midi_track(track)
  local item_count =
    reaper.CountTrackMediaItems(track)

  if item_count == 0 then
    return false
  end

  local found_midi = false

  for i = 0, item_count - 1 do
    local item =
      reaper.GetTrackMediaItem(track, i)

    local take =
      item and reaper.GetActiveTake(item)

    if take then
      if reaper.TakeIsMIDI(take) then
        found_midi = true
      else
        -- Mixed audio/MIDI tracks are treated as audio.
        return false
      end
    end
  end

  return found_midi
end

local function midi_track_has_data(track)
  local item_count =
    reaper.CountTrackMediaItems(track)

  for i = 0, item_count - 1 do
    local item =
      reaper.GetTrackMediaItem(track, i)

    local take =
      item and reaper.GetActiveTake(item)

    if take and reaper.TakeIsMIDI(take) then
      local ok, note_count, cc_count, text_count =
        reaper.MIDI_CountEvts(take)

      if ok and (
          note_count > 0
          or cc_count > 0
          or text_count > 0
        ) then
        return true
      end
    end
  end

  return false
end

local function remove_empty_midi_tracks(tracks)
  local kept_tracks = {}

  for _, track in ipairs(tracks) do
    if is_midi_track(track)
        and not midi_track_has_data(track) then
      -- Imported tempo markers and project markers remain
      -- after the empty MIDI track is deleted.
      reaper.DeleteTrack(track)
    else
      kept_tracks[#kept_tracks + 1] = track
    end
  end

  return kept_tracks
end

------------------------------------------------------------
-- TRACK-NAME CLEANUP
------------------------------------------------------------

local function clean_name(name)
  name = name or ""

  -- Remove the filename extension.
  name = name:gsub("%.[%w]+$", "")

  -- 19 GTR Lead -> GTR Lead
  -- 19_GTR Lead -> GTR Lead
  name = name:gsub(
    "^%s*%d+[%s%-%._]+",
    ""
  )

  return name:match("^%s*(.-)%s*$")
end

local function clean_imported_track_names(tracks)
  if not CONFIG.clean_track_names then
    return
  end

  for _, track in ipairs(tracks) do
    local take_name = get_take_name(track)
    local current_name = get_track_name(track)

    local source_name =
      take_name ~= "" and take_name or current_name

    local new_name = clean_name(source_name)

    if new_name ~= "" then
      reaper.GetSetMediaTrackInfo_String(
        track,
        "P_NAME",
        new_name,
        true
      )
    end
  end
end

------------------------------------------------------------
-- CLASSIFICATION
------------------------------------------------------------

local function classify(name)
  local n = normalize(name)
  local k = CONFIG.keywords

  -- FX always goes to XTRA.
  if matches_any(n, k.fx) then
    return "XTRA"
  end

  ----------------------------------------------------------
  -- DRUMS
  ----------------------------------------------------------

  if matches_any(n, k.kick) then
    return "KICK"
  end

  if matches_any(n, k.snare) then
    return "SNARE"
  end

  if matches_any(n, k.toms)
      or n:match(" t%d+ ")
      or n:match(" t %d+ ")
      or n:match(" rt%d+ ")
      or n:match(" rt %d+ ")
      or n:match(" fl%d+ ")
      or n:match(" fl %d+ ") then
    return "TOMS"
  end

  if matches_any(n, k.cymbals) then
    return "OH"
  end

  if matches_any(n, k.rooms) then
    return "ROOMS"
  end

  ----------------------------------------------------------
  -- BASS
  ----------------------------------------------------------

  if matches_any(n, k.bass) then
    return "BASS"
  end

  ----------------------------------------------------------
  -- GUITARS
  ----------------------------------------------------------

  local is_guitar =
    matches_any(n, k.guitar)

  local is_lead_guitar =
    matches_any(n, k.lead_guitar)

  if is_guitar and is_lead_guitar then
    return "LEAD GTRS"
  end

  if matches_any(n, k.clean_guitar) then
    return "CLEAN GTRS"
  end

  if is_guitar
      or matches_any(n, k.main_guitar) then
    return "MAIN GTRS"
  end

  ----------------------------------------------------------
  -- VOCALS
  ----------------------------------------------------------

  if matches_any(n, k.scream_vocals) then
    return "SCREAM VOCALS"
  end

  if matches_any(n, k.bg_vocals) then
    return "BG VOCALS"
  end

  if matches_any(n, k.harm_vocals) then
    return "HARM VOCALS"
  end

  if matches_any(n, k.group_vocals) then
    return "GROUP VOCALS"
  end

  if matches_any(n, k.main_vocals) then
    return "MAIN VOCALS"
  end

  return "XTRA"
end

------------------------------------------------------------
-- TEMPLATE FOLDERS
------------------------------------------------------------

local function find_template_folders()
  local wanted = {}
  local found = {}

  for _, name in ipairs(CONFIG.routes) do
    wanted[name] = true
  end

  for i = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, i)
    local key = folder_key(get_track_name(track))

    if wanted[key] and not found[key] then
      found[key] = track
    end
  end

  return found
end

local function validate_template(folders)
  local missing = {}

  for _, name in ipairs(CONFIG.routes) do
    -- MIDI is created dynamically when needed.
    if name ~= "MIDI"
        and not folders[name] then
      missing[#missing + 1] = name
    end
  end

  if #missing == 0 then
    return true
  end

  table.sort(missing)

  reaper.ShowMessageBox(
    "The following template folders are missing:\n\n"
      .. table.concat(missing, "\n")
      .. "\n\nNo files were imported.",
    "Template validation failed",
    0
  )

  return false
end

local function ensure_midi_folder(folders)
  -- Reuse an existing MIDI folder.
  if folders["MIDI"] then
    return folders["MIDI"]
  end

  -- Otherwise create it at the end of the project.
  local index = reaper.CountTracks(0)

  reaper.InsertTrackAtIndex(index, false)

  local folder = reaper.GetTrack(0, index)

  reaper.GetSetMediaTrackInfo_String(
    folder,
    "P_NAME",
    "MIDI",
    true
  )

  folders["MIDI"] = folder

  return folder
end

------------------------------------------------------------
-- PANNING
------------------------------------------------------------

local function detect_pan(track)
  local n = normalize(track_label(track))

  local has_left =
    contains(n, "l")
    or contains(n, "left")

  local has_right =
    contains(n, "r")
    or contains(n, "right")

  -- Leave ambiguous names centered.
  if has_left and has_right then
    return nil
  end

  if has_left then
    return -1.0
  end

  if has_right then
    return 1.0
  end

  return nil
end

------------------------------------------------------------
-- AUDIO TRACK SETTINGS
------------------------------------------------------------

local function apply_imported_track_settings(tracks)
  for _, track in ipairs(tracks) do
    if reaper.ValidatePtr2(
        0,
        track,
        "MediaTrack*"
      ) then
      -- Do not adjust MIDI volume or pan.
      if not is_midi_track(track) then
        local folder_depth =
          reaper.GetMediaTrackInfo_Value(
            track,
            "I_FOLDERDEPTH"
          )

        local has_media =
          reaper.CountTrackMediaItems(track) > 0

        local is_folder = folder_depth > 0

        local is_mix =
          folder_key(get_track_name(track)) == "MIX"

        if not is_folder
            and not is_mix
            and has_media then
          reaper.SetMediaTrackInfo_Value(
            track,
            "D_VOL",
            TARGET_VOLUME
          )

          local pan = detect_pan(track)

          if pan then
            reaper.SetMediaTrackInfo_Value(
              track,
              "D_PAN",
              pan
            )
          end
        end
      end
    end
  end
end

------------------------------------------------------------
-- IMPORT HELPERS
------------------------------------------------------------

local function remember_existing_tracks()
  local existing = {}

  for i = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, i)

    existing[
      reaper.GetTrackGUID(track)
    ] = true
  end

  return existing
end

local function find_imported_tracks(existing)
  local imported = {}

  for i = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, i)
    local guid = reaper.GetTrackGUID(track)

    if not existing[guid]
        and reaper.CountTrackMediaItems(track) > 0 then
      imported[#imported + 1] = track
    end
  end

  return imported
end

local function delete_new_tracks(existing)
  for i = reaper.CountTracks(0) - 1, 0, -1 do
    local track = reaper.GetTrack(0, i)
    local guid = reaper.GetTrackGUID(track)

    if not existing[guid] then
      reaper.DeleteTrack(track)
    end
  end
end

------------------------------------------------------------
-- MAIN
------------------------------------------------------------

local function main()
  local folders = find_template_folders()

  if not validate_template(folders) then
    return
  end

  local existing_tracks =
    remember_existing_tracks()

  begin_undo()

  -- Prevent the first file from being imported onto a
  -- template folder track.
  local import_index = reaper.CountTracks(0)

  reaper.InsertTrackAtIndex(
    import_index,
    false
  )

  local import_target =
    reaper.GetTrack(0, import_index)

  reaper.GetSetMediaTrackInfo_String(
    import_target,
    "P_NAME",
    "__IMPORT_TARGET__",
    true
  )

  reaper.SetOnlyTrackSelected(import_target)

  -- Opens the media file dialog and REAPER's native MIDI
  -- import dialog when MIDI files are selected.
  reaper.Main_OnCommand(40018, 0)

  local imported_tracks =
    find_imported_tracks(existing_tracks)

  if #imported_tracks == 0 then
    delete_new_tracks(existing_tracks)

    reaper.TrackList_AdjustWindows(false)
    reaper.UpdateArrange()

    end_undo("Cancelled media import")
    return
  end

  -- Remove the temporary track if REAPER left it empty.
  if reaper.ValidatePtr2(
      0,
      import_target,
      "MediaTrack*"
    )
    and reaper.CountTrackMediaItems(import_target) == 0 then
    reaper.DeleteTrack(import_target)
  end

  clean_imported_track_names(imported_tracks)

  -- Remove MIDI tracks that contain no MIDI events.
  imported_tracks =
    remove_empty_midi_tracks(imported_tracks)

  -- A tempo-only MIDI file may leave no track after its
  -- tempo map and markers have been imported.
  if #imported_tracks == 0 then
    reaper.TrackList_AdjustWindows(false)
    reaper.UpdateArrange()

    end_undo(
      "Import MIDI tempo map and markers"
    )

    return
  end

  -- Create or reuse MIDI folder only if MIDI tracks remain.
  local has_midi_tracks = false

  for _, track in ipairs(imported_tracks) do
    if is_midi_track(track) then
      has_midi_tracks = true
      break
    end
  end

  if has_midi_tracks then
    ensure_midi_folder(folders)
  end

  ----------------------------------------------------------
  -- CLASSIFY
  ----------------------------------------------------------

  local categorized = {}

  for _, route in ipairs(CONFIG.routes) do
    categorized[route] = {}
  end

  for _, track in ipairs(imported_tracks) do
    local destination

    if is_midi_track(track) then
      destination = "MIDI"
    else
      destination = classify(track_label(track))
    end

    categorized[destination][
      #categorized[destination] + 1
    ] = track
  end

  ----------------------------------------------------------
  -- MOVE TRACKS
  ----------------------------------------------------------

  lock_ui()

  for _, destination in ipairs(CONFIG.routes) do
    local tracks = categorized[destination]
    local folder = folders[destination]

    if #tracks > 0 and folder then
      reaper.SetOnlyTrackSelected(tracks[1])

      for i = 2, #tracks do
        reaper.SetTrackSelected(
          tracks[i],
          true
        )
      end

      local folder_index = math.floor(
        reaper.GetMediaTrackInfo_Value(
          folder,
          "IP_TRACKNUMBER"
        )
      ) - 1

      reaper.ReorderSelectedTracks(
        folder_index + 1,
        1
      )
    end
  end

  ----------------------------------------------------------
  -- AUDIO VOLUME AND PANNING
  ----------------------------------------------------------

  apply_imported_track_settings(
    imported_tracks
  )

  ----------------------------------------------------------
  -- FINISH
  ----------------------------------------------------------

  reaper.Main_OnCommand(40297, 0)

  for _, track in ipairs(imported_tracks) do
    if reaper.ValidatePtr2(
        0,
        track,
        "MediaTrack*"
      ) then
      reaper.SetTrackSelected(track, true)
    end
  end

  unlock_ui()

  reaper.TrackList_AdjustWindows(false)
  reaper.UpdateArrange()

  end_undo("Import and organize tracks")
end

------------------------------------------------------------
-- PROTECTED EXECUTION
------------------------------------------------------------

local ok, error_message =
  xpcall(main, debug.traceback)

if not ok then
  unlock_ui()
  end_undo("Import organizer interrupted")

  reaper.TrackList_AdjustWindows(false)
  reaper.UpdateArrange()

  reaper.ShowMessageBox(
    "The script encountered an error:\n\n"
      .. tostring(error_message)
      .. "\n\nYou can undo the operation if necessary.",
    "Import organizer error",
    0
  )
end