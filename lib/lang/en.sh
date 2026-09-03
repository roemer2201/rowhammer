#!/usr/bin/env bash
#
# lib/lang/en.sh
#
# Description:
#   English texts for rowhammer (see lib/i18n.sh). Sourced by i18n_init
#   when the resolved language is "en"; it assigns the whole I18N array,
#   so switching the language at runtime cannot leave a stale entry of
#   the previous one behind.
#   Translated from lib/lang/de.sh, which is the reference: the keys,
#   their order and the comments explaining a format string or a width
#   constraint live there. Every line of a screen text has to stay
#   within the 46 characters the 48-column minimum terminal leaves next
#   to the two-column menu indent, the result box lines within its 18
#   columns and the HUD labels within six.
#   Library file: sourced by lib/i18n.sh, not meant to be executed directly.
#
# Version: 1.7.0  (2026-08-11)

# Guard: this file is a library and must be sourced, not executed.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    printf 'lib/lang/en.sh is a library; source it from rowhammer.sh\n' >&2
    exit 2
fi

I18N=(
    # --- Menu chrome ------------------------------------------------------
    [menu_any_key]="Press any key..."
    [menu_nav]="Arrows/w/s: select   Enter: OK   ESC: back"
    [menu_nav_cancel]="Arrows/w/s: select   Enter: OK   ESC: cancel"
    [menu_more_up]="      ^ %d more"
    [menu_more_down]="      v %d more"
    [menu_page]="%s (page %d/%d)"
    [menu_back]="Back"

    # --- Main menu --------------------------------------------------------
    [main_resume]="Resume"
    [main_single]="Singleplayer"
    [main_multi]="Multiplayer"
    [main_highscores]="Highscores"
    [main_wonders]="Wonders"
    [main_stats]="Statistics"
    [main_demos]="Demos"
    [main_settings]="Settings"
    [main_help]="Manual"
    [main_quit]="Quit"

    # --- Multiplayer (1.1.0) ----------------------------------------------
    # Menu, session search, lobby and their messages. Every line stays
    # within the 46 characters a 48-column terminal leaves beside the
    # menu indent.
    [mp_host]="Open a session"
    [mp_join]="Join a session"
    [mp_direct]="Connect directly"
    [mp_no_socat]="The multiplayer needs socat, and it is not
installed on this machine.

Debian/Ubuntu:  apt install socat
Fedora/RHEL:    dnf install socat

The singleplayer runs on without it."
    [mp_host_failed]="The session could not be opened.

The port may be taken, or the session
directory may not be writable."
    [mp_search_failed]="The search could not be started.

The port may be taken."
    [mp_searching]="Looking for sessions (UDP port %s)..."
    # Order: name, address, players, maximum, state.
    [mp_session_entry]="%-12.12s %-15.15s %s/%s %s"
    [mp_state_lobby]="lobby"
    [mp_state_play]="running"
    [mp_none]="No session found"
    [mp_search_again]="Search again"
    [mp_direct_body]="Address of the machine that opened the
session - with a port when it differs from
the default:

  192.168.1.23   or   192.168.1.23:27301"
    [mp_bad_address]="That is not a valid address.

Allowed is an IPv4 address or a host name,
optionally followed by :port."
    [mp_join_failed]="The connection was not established.

Is the session still running, and are both
machines on the same network?"
    [mp_reason]="Reason:"
    # --- The host's session settings (1.1.0) ------------------------------
    # The mode decides the win condition, garbage is a switch beside it.
    # Both are shown in every player's lobby and not only in the host's -
    # they decide what the round is played for.
    [mp_settings]="Settings"
    [mp_settings_title]="Multiplayer - settings"
    [mp_settings_body]="Only you as the host change them;
everybody sees them in their lobby."
    [mp_settings_nav]="Enter/arrows: change   ESC: back"
    [mp_setup_mode]="Mode: %s (%s)"
    [mp_setup_garbage]="Garbage rows: %s"
    [mp_setup_limit_sprint]="Time limit: %s minutes"
    [mp_setup_limit_ultra]="Target: %s rows"
    [mp_on]="on"
    [mp_off]="off"
    # The names of the three multiplayer modes and, separately, who wins
    # in them. The name says how a round runs, the win condition says what
    # it is played for - and in a lobby the second is the more important
    # question.
    [mpmode_survival]="Survival"
    [mpmode_sprint]="Sprint"
    [mpmode_ultra]="Ultra"
    [mpwin_survival]="last one standing"
    [mpwin_sprint]="most rows"
    [mpwin_ultra]="first to the target"
    # --- Host handover and a closed session (1.2.0) -----------------------
    # When the host leaves the lobby their hub ends - the session moves on
    # to the next player. The notice is acknowledged with Enter, because
    # the menu below it is not the one that was there before.
    [mp_host_left_title]="The host has left the lobby"
    [mp_host_left_body]="The session carries on - it has moved to the next
player. Everybody's ready mark has been
cleared."
    [mp_host_new]="New host: %s"
    [mp_host_you]="You are the host now and start the round."
    [mp_host_confirm]="Enter: got it"
    [mp_closed_host]="The host closed the lobby.

There was nobody left who could have taken
the session over."
    [mp_closed_failed]="The session could not be taken over.

The next player could not open a session of
their own, so this one is over."
    [mp_closed_silent]="The session has stopped answering.

The host is gone, or the network between you
broke down."
    [mp_lobby_title]="Multiplayer - lobby"
    [mp_lobby_session]="Session: %s"
    [mp_lobby_addr]="Address to pass on: %s:%s"
    [mp_lobby_alone]="Waiting for a second player..."
    [mp_start]="Start the round"
    [mp_ready]="Ready"
    [mp_unready]="Not ready after all"
    [mp_leave]="Leave the lobby"
    [mp_you]="(you)"
    [mp_is_host]="host"
    [mp_is_ready]="ready"
    [mp_is_waiting]="waiting"
    [mp_countdown]="Starting in %s..."
    [mp_lost_body]="The connection to the session is gone.

The host ended it, or the network was away
for a moment."
    [mp_pause_note]="The others play on - only your own board
stops here. So make up your mind quickly."
    [mp_end_tail]="The round is recorded and over afterwards;
the others play it to the end."
    [mp_suspended]="A suspended round is still waiting in the
main menu.

A multiplayer round runs through that very
state, so finish the suspended round first
(Resume)."

    [round_state]="%d lines, %d rows, level %d."
    [quit_title]="Really quit?"
    [quit_yes]="Yes, quit"
    [confirm_no]="No, go back"
    [quit_head]="A suspended round is still waiting:"
    [quit_tail]="Quitting records it, after which it cannot
be resumed any more."

    # --- Game modes -------------------------------------------------------
    [mode_marathon]="Marathon"
    [mode_ultra]="Ultra"
    [mode_sprint]="Sprint"
    [mode_timeattack]="Time Attack"
    [mode_timeattack_short]="TimeAtk"
    # "Hochwasser" is German for "flood" and the name the mode was asked
    # for; the English list calls it what it is, like every other entry
    # here - the mode identifier on the command line stays "flood".
    [mode_flood]="Flood"
    [mode_flood_short]="Flood"
    # The multiplayer mode (1.1.0). It is not an entry of the
    # singleplayer menu, but it is one of the two pickers that look back
    # (highscores, statistics) and it names itself wherever a round names
    # its mode.
    [mode_versus]="Multiplayer"
    # The short form for the demo list, which leaves the mode eight
    # columns (demo_scan in lib/demo.sh) - the same reason Time Attack
    # and Hochwasser have one.
    [mode_versus_short]="Versus"
    # The entry_* forms are the bracketed description the three pickers put
    # behind the name; menu_mode_entries (lib/menu.sh) pads the names so the
    # descriptions line up in one column (see lib/lang/de.sh).
    [entry_marathon]="(endless, until game over)"
    [entry_ultra]="(%s rows against the clock)"
    [entry_sprint]="(%s minutes for rows)"
    [entry_timeattack]="(%s + %ss per row)"
    [entry_flood]="(a row every %s sec.)"
    [entry_versus]="(2 to %s players)"

    # --- Singleplayer and pause menu --------------------------------------
    [sp_title]="Singleplayer"
    [pause_title]="Pause"
    [pause_restart]="Restart"
    [pause_to_menu]="To the main menu (round suspended)"
    [pause_end]="End the round"
    [restart_title]="Really restart?"
    [restart_yes]="Yes, restart"
    [restart_head]="The running round is given up:"
    [restart_tail]="It is recorded (wonders and statistics) and
a fresh one starts in the same mode."
    [end_title]="Really end the round?"
    [end_yes]="Yes, end it"
    [end_head]="The running round is ended:"
    [end_tail]="It is recorded and cannot be resumed
afterwards."

    # --- Settings ---------------------------------------------------------
    [set_title]="Settings"
    [set_keys]="Configure keys"
    [set_theme]="Color theme (now: %s)"
    [set_name]="Change player name (now: %s)"
    [set_demo]="Demo recording (now: %s)"
    [set_lang]="Language (now: %s)"
    [on]="on"
    [off]="off"
    [theme_title]="Pick a color theme"
    [theme_guideline]="Guideline"
    [theme_classic]="Classic"
    [theme_mono]="Monochrome"
    [theme_colorblind]="Colorblind"
    [lang_title]="Pick a language"
    [lang_auto]="Automatic"

    # --- Key bindings -----------------------------------------------------
    [keylabel_KEY_LEFT]="Left"
    [keylabel_KEY_RIGHT]="Right"
    [keylabel_KEY_ROT_CW]="Rotate right"
    [keylabel_KEY_ROT_CCW]="Rotate left"
    [keylabel_KEY_SOFT]="Soft drop"
    [keylabel_KEY_HARD]="Hard drop"
    [keylabel_KEY_PAUSE]="Pause"
    [keylabel_KEY_QUIT]="Back to the menu"
    [keylabel_KEY_HOLD]="Hold"
    [rebind_ask]="Press the new key for \"%s\""
    [rebind_current]="(now: %s, ESC = cancel)"
    [rebind_reserved_menu]="This key is reserved for menu navigation."
    [rebind_reserved_r]="The key 'r' is reserved for the restart on
the game over screen."
    [rebind_invalid]="Invalid key. Allowed are a-z, 0-9 and space."
    [rebind_taken]="The key [%s] is already taken."

    [key_space]="space"
    [key_arrow_left]="arrow left"
    [key_arrow_right]="arrow right"
    [key_arrow_down]="arrow down"
    [key_space_up]="space, arrow up"
    [key_arrows_lr]="arrow left/right"

    # --- Text input -------------------------------------------------------
    [input_hint_type]="Typing replaces the marked text."
    [input_hint_keys]="Enter: OK   ESC: leave unchanged"
    [name_title]="Player name"
    [name_current]="Current name: %s"
    [name_rules]="Allowed are at most %d characters from
A-Z a-z 0-9 space _ -"
    [round_title]="Round finished"
    [round_mode]="Mode: %s"
    [round_rows]="Rows: %d   Lines: %d"
    [round_level]="Level: %d   Time: %s"
    # Place in the list of the round's mode: 1 = rank, 2 = list length.
    # A round without a place is never asked for a name (since 1.0.1),
    # so there is no wording for that case.
    [round_rank]="Highscore list: rank %d of %d"
    [round_ask_name]="Name for the highscore list:"

    # --- Demos ------------------------------------------------------------
    [demos_title]="Demos"
    [demos_title_kept]="Demos (%d)   * = holds a highscore"
    [demos_title_count]="Demos (%d/%d)"
    [demos_none]="No recordings yet."
    [demos_none_on]="Every round played is recorded
automatically and shows up here as soon as
it has ended. The %d newest rounds
are kept."
    [demos_none_off]="Demo recording is switched off at the
moment. You can switch it back on in the
settings."
    [demo_title]="Demo"
    [demo_play]="Play"
    [demo_delete]="Delete"
    [demo_broken]="(broken)"
    [demo_busy]="A suspended round is still waiting.

A replay uses the same board as the running
round and would throw it away. Resume it or
end it through the pause menu, then this
will work."
    [demo_del_title]="Delete the demo?"
    [demo_del_yes]="Yes, delete it"
    [demo_del_no]="No, keep it"
    [demo_del_hint]="It still holds a highscore entry."
    [demo_del_body]="The recording is really deleted and
cannot be brought back."
    [demo_del_failed]="The recording could not be deleted:"
    [demo_invalid]="This recording is damaged or comes from
another version and cannot be played.

You can delete it in the demo menu."

    # --- HUD --------------------------------------------------------------
    [hud_hold]="Hold"
    [hud_next]="Next"
    [hud_lines]="Lines"
    [hud_rows]="Rows"
    [hud_level]="Level"
    [hud_gold]="Gold"
    [hud_silver]="Silver"
    [hud_hammer]="Hammer"
    [hud_time]="Time"
    [hud_pieces]="Pieces"
    [hud_goal]="Goal"
    [hud_left]="Left"
    [hud_flood]="Flood"
    [hud_demo]="Demo"
    # Multiplayer: the garbage rows waiting and the number of players
    # still in the round. Six characters, like every HUD label.
    [hud_garbage]="Garb"
    [hud_alive]="Alive"
    # One character per marker, which is all there is room for next to a
    # mini board: garbage incoming, and a player who is out.
    [hud_peer_warn]="!"
    [hud_peer_ko]="K.O."

    # --- Result box over the board ----------------------------------------
    [box_paused]="      PAUSED      "
    [box_game_over]="    GAME OVER"
    [box_ultra_clear]="    ULTRA CLEAR"
    [box_sprint_end]="    SPRINT END"
    [box_time_up]="    TIME UP"
    [box_demo_end]="    DEMO END"
    [box_rows]="   Rows %d"
    [box_time]="   Time %s"
    [box_rows_goal]="  Rows %d/%d"
    [box_time_goal]="  Time %s/%s"
    [box_rank]="  %s #%d"
    [box_rank_marathon]="  Highscore #%d"
    [box_end_over]="  Game Over"
    [box_end_goal]="  Goal reached"
    [box_end_quit]="  Given up"
    [box_restart]="  r = restart"
    [box_menu]="  %s = menu"
    [box_demo_again]="  r = again"
    [box_demo_back]="  %s = back"
    [box_mp_win]="       YOU WIN"
    [box_mp_over]="    ROUND OVER"
    [box_mp_ko]="      K. O."
    [box_mp_place]="   Place %d"
    [box_mp_watch]="  You are watching"

    # --- Too-small terminal overlay ---------------------------------------
    [resize_head]="resize:"
    [resize_need]="need %sx%s"
    [resize_now]="now %sx%s"

    # --- World wonders ----------------------------------------------------
    [wonder_all_done]="All world wonders have been built!"
    [wonder_building]="Wonder %d/%d: %s"
    [wonder_finished]="%s is finished."
    [wonder_stage]="Stage %d/%d - %d/%d rows (%d%%)"
    [wonder_total]="Rows in total: %d"
    [wonder_nav]="Arrow le/ri: wonder   Enter/ESC: back"
    [wonder_mayan_temple]="Mayan Temple (Chichen Itza)"
    [wonder_stonehenge]="Stonehenge"
    [wonder_sphinx]="Great Sphinx of Giza"
    [wonder_pantheon]="Pantheon (Rome)"
    [wonder_great_wall]="Great Wall of China"
    [wonder_taj_mahal]="Taj Mahal"
    [wonder_st_basils]="St Basil's Cathedral (Moscow)"

    # --- Highscore lists --------------------------------------------------
    [hs_title]="Highscores"
    [hs_col_no]="No"
    [hs_col_name]="Name"
    [hs_col_rows]="Rows"
    [hs_col_time]="Time"
    [hs_col_lines]="Lines"
    [hs_col_date]="Date"
    [hs_lbl_gold]="Gold"
    [hs_lbl_silver]="Silv"
    # Footer and legend of the list browser (highscore_browse). The
    # footer names the four things the keys do; the legend appears only
    # when at least one entry has a recording.
    [hs_nav]="^v entry  <> page  Enter demo  ESC back"
    [hs_legend_demo]="* = recording available"
    [hs_no_demo]="There is no recording for this entry.

It was deleted, recording was switched off
while the round was played, or the entry is
older than the demo feature."
    [hs_empty]="No entries yet."
    [hs_empty_marathon]="Play a round to get onto the list."
    [hs_empty_ultra]="Reach the goal of %s rows in an Ultra
round to get onto the list. An attempt that
tops out before that is not recorded."
    [hs_empty_sprint]="Play a Sprint round over the full
%s minutes to get onto the list. An
attempt that tops out before that is not
recorded."
    [hs_empty_timeattack]="Play a Time Attack round: it starts with
%s minutes on the clock and every row
buys one second. Every run is recorded -
a top-out before the time is up as well."
    [hs_empty_flood]="Play a Flood round: every %s seconds a
row rises from below. Every round is
recorded - it ends in a game over either
way."
    [hs_empty_versus]="Play a multiplayer round. What is ranked
are your own rows, won or lost; how many
played along and who won is deliberately
not part of this list."

    # --- Statistics -------------------------------------------------------
    [stats_title]="Statistics"
    [stats_all]="All-time (every mode)"
    [stats_lines]="Rows cleared:"
    [stats_bonus]="Bonus rows:"
    [stats_ratio]="Ratio rows/bonus:"
    [stats_total]="Rows in total (weighted):"
    [stats_gold]="Gold squares:"
    [stats_silver]="Silver squares:"
    [stats_hammer]="Rowhammers (4 rows):"
    [stats_pieces]="Pieces placed:"
    [stats_playtime]="Play time in total:"
    [stats_ppm]="Pieces/minute (PCS/min):"
    [stats_recent_head]="Recent rounds (newest first):"
    [stats_recent_none]="No rounds yet."
    [stats_recent_rows]="Rows"
    [stats_recent_lines]="Lines"
    [stats_recent_bonus]="Bonus"
    [stats_recent_ratio]="Rows/bonus"
    [stats_modes_head]="Rounds per game mode:"
    [stats_rounds]="Rounds:"
    [stats_rounds_total]="Rounds in total:"
    [stats_rows_per_round]="Rows per round:"
    [stats_goal_rate]="Success rate:"
    [stats_goal_ultra]="of those goal reached:"
    [stats_goal_sprint]="of those full time:"
    [stats_goal_timeattack]="of those clock run down:"
    [stats_goal_versus]="of those won:"

    # --- Manual -----------------------------------------------------------
    [help_title]="Manual"
    [help_nav]="Arrow le/ri: page   Enter/ESC: back"
    [help_p0]="rowhammer is a Tetris game for the terminal,
modeled after \"The New Tetris\" (N64).

Pieces have to be stacked so that rows fill
up completely: a full row is cleared and
scored as \"Rows\" - which is at the same
time the round's score.

The pieces come out of a bag of 63: each of
the seven types nine times, shuffled into a
random order.

Every cleared row raises the level and the
pieces fall faster. Once a placed piece
sticks out above the field or a new piece has
no room left, the round is over."
    [help_p1_head]="Controls during a round (the letter keys
can be changed in the settings):
"
    [help_key_left]="Move left"
    [help_key_right]="Move right"
    [help_key_rot_cw]="Rotate right"
    [help_key_rot_ccw]="Rotate left"
    [help_key_soft]="Soft drop"
    [help_key_hard]="Hard drop"
    [help_key_hold]="Hold / swap"
    [help_key_pause]="Pause"
    [help_key_quit]="Pause menu"
    [help_p1_tail]="
Soft drop makes the piece fall faster,
hard drop locks it right away.
Restart: [r] on game over or in the pause
menu. In the menus: arrows or w/s select,
Enter confirms, ESC goes back."
    [help_p2]="Preview and hold

Top right (\"Next\") are the three upcoming
pieces - enough lead time to plan the
stack.

Top left is the hold slot. With
%s the current piece moves there;
if one is already in it, the two swap
places and the held piece re-enters in its
spawn position.

Only one swap per piece is allowed - the
next swap is possible after the next piece
has locked. That way an I piece can be kept
for the big clear, or an awkward piece
parked for a moment."
    [help_p3_head]="Four complete, uncut pieces that fill a
4x4 square exactly become a bonus block:
"
    [help_sq_gold]="Gold"
    [help_sq_gold_text]="all four pieces of the same type"
    [help_sq_silver]="Silver"
    [help_sq_silver_text]="four mixed types"
    [help_p3_mid]="
A piece a cleared row has already cut
through does not count any more.

Clearing a row is worth (in rows):"
    [help_row_base]="base value per row"
    [help_row_silver]="per silver square in the row"
    [help_row_gold]="per gold square in the row"
    [help_row_hammer]="rowhammer (4 rows at once)"
    [help_p3_tail]="
A rowhammer straight through two complete
gold squares is worth 4+1+80 = 85 rows."
    [help_p4_head]="All cleared rows add up across the rounds
(those of an abandoned round as well) and
build seven world wonders one after the
other.

Weighted rows per world wonder:"
    [help_p4_tail]="
\"Wonders\" shows the construction site: it
grows from the bottom and stands finished at
100 percent - as it does after a round. The
arrow keys page back through finished ones."
    [help_p5_head]="Game modes (\"Singleplayer\" menu entry):

Marathon - the endless round. It ends when
  a new piece has no room left.
"
    [help_p5_ultra]="Ultra - %s rows as fast as possible.
  The result is the play time; the round
  ends the moment the goal is reached.
"
    [help_p5_sprint]="Sprint - as many rows as possible within
  %s minutes. The result is the rows; the
  round ends when the time is up.
"
    [help_p6_head]="Game modes (continued):
"
    [help_p6_timeattack]="Time Attack - %s minutes on a clock that
  runs backwards; every row buys %s sec.
  The result is the rows; the round ends
  at 00:00 - or earlier on a game over.
"
    [help_p6_flood]="Flood - every %s seconds a full row with
  a single gap rises from below and the
  board moves up. Marathon otherwise: the
  result is the rows, the round ends on top."
    [help_p7]="Highscore lists (\"Highscores\" entry):

Every mode has a list of its own. All of
them rank by rows, only Ultra ranks by the
shortest time.

For Ultra and Sprint only a run that
reached its goal resp. played its full time
counts - a game over before that is not
recorded.

Every Time Attack and every Flood round
counts, by contrast: its rows are the same
achievement either way, and topping out
early simply means fewer of them.

The rows and counters of an abandoned round
always feed the wonders and the statistics."
    [help_p8_head]="Demos (\"Demos\" menu entry):

Every round played is recorded and can be
watched again later. What is recorded are
the moves, not the screen - a replay really
plays the round once more.
"
    [help_p8_kept]="The %d newest rounds are kept;"
    [help_p8_mid]="recordings marked * still hold a highscore
and are kept beyond that. Single ones can
be deleted in the demo menu, the recording
switched off in the settings.
The highscore lists play them with Enter.

During a replay:"
    [help_demo_pause]="Pause / resume"
    [help_demo_speed]="Speed"
    [help_demo_back]="Back"

    # --- One-time rename of the Marathon highscore file (0.51.0) ----------
    # Printed before the terminal is touched, like the reset dialog.
    # Arguments: old path, new path.
    [highscore_renamed]="Highscore list renamed: %s -> %s"


    # Page 10: the multiplayer (1.1.0). The player count and the port
    # come from the live constants, so a retuned value cannot leave the
    # page lying.
    [help_p9_head]="Multiplayer (on the local network)

Everybody plays their own board, all of them
with the same piece sequence. Whoever builds
out of the field drops out and watches on."
    [help_p9_players]="From 2 to %s people play; one opens the
session, the others find it on the network
(UDP port %s) or type in its address."
    [help_p9_tail]="In the lobby the host settles how the round
is won - last one standing, most rows in the
time (Sprint) or first to the target (Ultra) -
and whether cleared rows send garbage to the
opponents (off to begin with). Everybody sees
it. There is no pause. Only your own
achievement is recorded. Needs socat."

    # --- Reset dialog (runs before the terminal is touched) ---------------
    [reset_affects]="Reset \"%s\" affects these files in %s:"
    [reset_absent]="(not present)"
    [reset_note]="Nothing is deleted; the files are moved to <file>-YYYYMMDDhhmmss.bak."
    [reset_confirm]="Are you sure you want to reset %s? [N/y] "
    [reset_aborted]="Reset cancelled, nothing was moved."
    [reset_wait]="A backup of this very second exists, waiting for the next one..."
    [reset_moved]="Moved: %s -> %s"
    [reset_done]="Reset successful"
    [reset_summary]="Reset \"%s\": %d file(s) backed up, %d not present."
)

# i18n_usage_text
# The --help output in this language; see lib/lang/de.sh for why this is
# a function with a quoted heredoc rather than an I18N entry.
i18n_usage_text() {
    cat <<'EOF'
Usage: rowhammer.sh [OPTIONS]

Terminal Tetris of the rowhammer project. Starts with a menu:
singleplayer (endless "Marathon", the timed "Ultra", "Sprint" or
"Time Attack" mode, or "Flood"),
multiplayer on the local network, highscores, wonders, statistics,
demos and settings.

Options:
  --seed N      Seed the piece randomizer for a reproducible sequence.
                Env: ROWHAMMER_SEED         Default: (random)
  --name NAME   Player name recorded with highscore entries (max. 16
                characters from A-Z a-z 0-9 space _ -).
                Env: ROWHAMMER_PLAYER_NAME  Default: Player
  --lang CODE   Language of the user interface: "de" (German), "en"
                (English) or "auto". "auto" takes the language from the
                locale variables (LC_ALL, LC_MESSAGES, LANG) and falls
                back to German when none of them names a supported
                language. Also selectable in the settings menu and
                persisted there.
                Env: ROWHAMMER_LANG         Default: auto
  --data-dir DIR
                Directory for all persistent game data: the config file
                rowhammer.conf, the highscore list, the savegame and
                the statistics file.
                Env: ROWHAMMER_DATA_DIR     Default: ~/.config/rowhammer
  --no-color    Disable ANSI colors. Each piece type is then drawn with
                its own two-letter glyph (II OO TT SS ZZ JJ LL) so blocks
                stay tellable apart after locking; gold squares show as
                "##", silver as "%%". Overrides --color-mode. The
                de-facto standard NO_COLOR variable
                (https://no-color.org/) is also honored: if it is set and
                non-empty, colors default to off; set ROWHAMMER_NO_COLOR=0
                to force them back on.
                Env: ROWHAMMER_NO_COLOR     Default: 0
  --color-mode MODE
                Color palette: "auto" detects 256-color support (tput
                colors, TERM, COLORTERM) and picks extended or basic;
                "basic" forces the 8/16-color ANSI palette; "extended"
                forces the xterm 256-color palette (guideline piece
                colors incl. a real orange L, richer gold/silver).
                Env: ROWHAMMER_COLOR_MODE   Default: auto
  --color-theme NAME
                Color scheme mapping piece and gold/silver colors:
                "guideline" (default), "classic", "mono" or "colorblind".
                Also selectable in the settings menu and persisted there.
                Env: ROWHAMMER_COLOR_THEME  Default: guideline
  --demo-record on|off
                Record every round as a demo that can be watched again
                from the "Demos" menu entry (see below). Also switchable
                in the settings menu and persisted there.
                Env: ROWHAMMER_DEMO_RECORD  Default: on
  --render-mode MODE
                How the play screen is pushed to the terminal:
                "partial" rewrites only the lines that changed since the
                previous frame (the default - about half the time and a
                fourteenth of the output of a full frame); "full"
                rewrites the whole 48x22 block on every frame, the way
                the renderer worked before 0.22.0. Use "full" on a
                terminal or multiplexer that draws the incremental
                update incorrectly, or to read whole frames out of the
                debug frame log.
                Env: ROWHAMMER_RENDER_MODE  Default: partial
  --mp-transport MODE
                How a multiplayer session is connected: "lan" over TCP
                on the local network (the default), or "unix" over a
                domain socket when everybody is logged into the same
                machine anyway.
                Env: ROWHAMMER_MP_TRANSPORT Default: lan
  --mp-port N   TCP and broadcast port of the multiplayer. A port that
                is taken is not an error: the host uses the next free
                one and announces that one.
                Env: ROWHAMMER_MP_PORT      Default: 27301
  --mp-dir DIR  Directory for the session files (in the "unix"
                transport also for the socket).
                Env: ROWHAMMER_MP_DIR
                Default: ${XDG_RUNTIME_DIR}/rowhammer
  --mp-max N    Upper bound on the players of a session, 2 to 5.
                Env: ROWHAMMER_MP_MAX       Default: 5
  --mp-session NAME
                Name of the session (1-16 characters of A-Z a-z 0-9
                _ -), the way the others see it in their list.
                Env: ROWHAMMER_MP_SESSION   Default: the user name
  --mp-view MODE
                How much of the opponents is drawn: "auto" (the
                default) takes the most detailed view the terminal has
                room for, "full" the mini boards, "compact" two lines
                per opponent, "score" one.
                Env: ROWHAMMER_MP_VIEW      Default: auto
  --mp-target MODE
                Who receives the garbage with three or more players:
                "random" (one opponent at random), "all" (every one of
                them the full amount) or "even" (split evenly). Only
                meaningful for the host - the hub decides.
                Env: ROWHAMMER_MP_TARGET    Default: random
  --mp-mode MODE
                What an opened session starts out with: "survival" (the
                last player in the field wins), "sprint" (most rows when
                the time limit is up) or "ultra" (first to the row
                target). The mode decides the win condition; the host can
                change it in the lobby at any time, where every player
                sees it.
                Env: ROWHAMMER_MP_MODE      Default: survival
  --mp-garbage on|off
                Whether cleared rows send garbage rows to the opponents -
                again only what the lobby starts out with. Off, because a
                round in which somebody else fills your board is the more
                demanding game: it should be switched on rather than
                happen unasked.
                Env: ROWHAMMER_MP_GARBAGE   Default: off
  --mp-bot      Test client without a terminal: joins a session and
                plays random moves, so a round with several players can
                be tested without several terminals.
                Env: ROWHAMMER_MP_BOT       Default: 0
  --reset TARGET
                Reset persistent data in the data directory and exit
                without starting the game. TARGET is one of:
                  config     the config file rowhammer.conf
                  stats      the statistics file stats
                  highscore  all highscore lists (highscore-marathon,
                             highscore-ultra, highscore-sprint,
                             highscore-timeattack, highscore-flood and
                             highscore-versus)
                  save       the savegame save (the wonder progress)
                  demo       the demo recordings (the demos directory)
                  all        all of the above
                Nothing is deleted: every affected file is moved to
                <file>-YYYYMMDDhhmmss.bak next to it, so a reset can be
                undone by moving the backup back. Running the same reset
                twice within one second waits for the next second rather
                than overwriting the backup just written.
                On a terminal the affected files are listed and
                confirmed first ([N/y], the default answer is no);
                without a tty (scripting, CI) the reset runs right away,
                since a waiting prompt would hang the script. Files that
                do not exist are not an error.
                Env: ROWHAMMER_RESET        Default: (no reset)
  --force       Answer confirmation questions with "yes" instead of
                asking. Combines with any other option; currently the
                only question asked outside the menus is the --reset
                one, so "--reset all --force" resets without a prompt.
                Env: ROWHAMMER_FORCE        Default: 0
  --debug       Enable the debug/trace mode: the session is recorded
                into log files (see below). Logs can grow to several
                megabytes in long sessions.
                Env: ROWHAMMER_DEBUG        Default: 0
  --debug-dir DIR
                Directory for the debug logs of this run.
                Env: ROWHAMMER_DEBUG_DIR
                Default: ~/.local/state/rowhammer/debug/<timestamp>.<pid>
  -h, --help    Show this help and exit.

Debug mode writes three correlated log files (shared millisecond
timestamps and a screen update counter) meant to make bug reports
reproducible:
  events.log    session header (version, terminal, seed, key bindings,
                config files) and every game action: spawns, moves and
                rotations (including blocked ones), falls, locks, square
                formation, line clears with credit details, hold, pause,
                menu choices, config saves and a board snapshot after
                every lock.
  input.log     every key press, raw bytes and mapped symbol.
  frames.log    every screen update byte for byte (1:1, ANSI included).
The log directory is printed when the game exits.

Controls (defaults). The letter key of every action is rebindable in the
settings menu; the arrow keys, space and w listed beside them are wired
in on top of the bindings and always work:
  arrow left / right          move piece (no letter key by default)
  d                           rotate clockwise
  a                           rotate counter-clockwise
  s or arrow down             soft drop
  space or arrow up           hard drop (no letter key by default)
  c or w                      hold / swap piece (once per piece)
  p                           pause / resume
  x or ESC                    open the pause menu: resume, restart the
                              round in the same mode, go to the main
                              menu with the round suspended (resumable
                              via the "Resume" entry in the main and
                              singleplayer menus), or end the round
  r                           restart (on the game over screen)

Square mechanics (The New Tetris): fill a 4x4 area with exactly four
complete, uncut pieces to form a square - gold if all four are the same
type, silver if mixed. Every cleared row is worth 1 row of credit, plus
10 per gold square and 5 per silver square it runs through (additive);
clearing 4 rows at once (a Tetris) adds 1 extra. The credit is shown as
"Rows" in the HUD and is the game's only score: cleared rows are the
sole source of points - drops, square formation and spins earn nothing.
Famous maximum for a single move: a Tetris through two complete gold
squares = 4 + 1 + 8 x 10 = 85.

Game modes (singleplayer menu): "Marathon" is the endless round
that ends on a top-out. "Ultra" is a race - clear 150 rows of credit as
fast as possible; the run ends the moment that target is reached and its
play time is the result. "Sprint" is the mirror image - score as many
rows of credit as possible within 3 minutes of play time; the run ends
when the time is up. "Time Attack" turns the clock into the stake: the
round starts with 1 minute of play time counting down and every row of
credit scored adds 1 second back, so the run lasts exactly as long as it
is kept fed and ends when the clock hits zero (or on a top-out before
that); the rows are the result. "Flood" ("Hochwasser") is Marathon under
rising water: every 20 seconds of play time a full row with a single gap
is pushed in from below and the board moves up with it, and the round
lasts until the stack reaches the ceiling; the rows are the result here
too. The HUD shows the goal and what is still
left of it (rows resp. time), resp. when the next flood row is due,
while such a round is going.
Each keeps its results in a list of its own - Ultra ranked by time
(<data-dir>/highscore-ultra, fastest first), Sprint, Time Attack and
Flood by rows (<data-dir>/highscore-sprint,
<data-dir>/highscore-timeattack, <data-dir>/highscore-flood) - so
they never displace the endless list's top ten. For Ultra and Sprint
only a run that got there is recorded: an attempt that topped out early
has neither a comparable time nor the full three minutes to score in.
Its rows still count toward the wonders and the statistics, like any
other round. Every Time Attack and every Flood round is recorded, by
contrast: its rows are the same achievement whether the clock, the water
or the stack ended it. The
"Highscores" main menu entry asks which of the five lists to show.

Wonders: the row credit of every round is added to a persistent counter
stored in <data-dir>/save. It builds seven world wonders in a fixed
sequence; the current construction site (ASCII art revealed bottom-up)
is shown after every round and via the "Wonders" main menu entry.

Demos: every round is recorded and can be watched again from the "Demos"
main menu entry, which lists the recordings with date, mode, play time
and rows and offers to play or to delete the one picked. What is recorded
are the moves, the gravity steps and the piece stream of the round - not
the screen - so a replay runs the round through the real game logic
again: it costs about 2 kB per minute of play, is independent of the
terminal size, the colors and the render mode of either session, and
lasts as long as the round did. While a demo plays, the pause key
(or space) halts it, the left/right arrows step the speed between 0.25x
and 4x, and the quit key returns to the list; "r" replays it from the
start once it has finished. Recordings live in <data-dir>/demos, the ten
newest are kept, and the round being recorded is written to a RAM disk
(XDG_RUNTIME_DIR resp. /dev/shm) so playing costs no disk writes.
Recording can be switched off with --demo-record off or in the settings
menu; a replay never enters the highscore lists, the wonder progress or
the statistics.

Statistics: every finished round also adds its cleared rows, bonus rows
(the gold/silver/Tetris part of the row credit) and the gold and silver
squares built to persistent all-time counters in <data-dir>/stats; the
results of the last three rounds (rows, bonus rows, squares) and the
number of rounds played per game mode - including how often Ultra
reached its target, Sprint played its full time and Time Attack ran its
clock down - are kept there as well. Every counter is also kept per
game mode, so the same figures can be read for Marathon, Ultra, Sprint,
Time Attack or Flood alone; the all-time counters stay what they always
were
and are not summed from those. The "Statistics" main menu entry asks
which of the two to show.

Settings (player name, language, color theme, key bindings, demo
recording) are stored in the config file
<data-dir>/rowhammer.conf, by default ~/.config/rowhammer/rowhammer.conf. The
best 10 rounds are kept in <data-dir>/highscore-marathon (Ultra: the
best 10 runs in <data-dir>/highscore-ultra, Sprint:
<data-dir>/highscore-sprint,
Time Attack: <data-dir>/highscore-timeattack, Flood:
<data-dir>/highscore-flood); all
five lists are shown under the
"Highscores" main menu entry, which asks for the mode first, and a
finished round reports its rank on the game over
screen. Key bindings can also be overridden
via environment variables ROWHAMMER_KEY_LEFT, ROWHAMMER_KEY_RIGHT,
ROWHAMMER_KEY_ROT_CW, ROWHAMMER_KEY_ROT_CCW, ROWHAMMER_KEY_SOFT,
ROWHAMMER_KEY_HARD, ROWHAMMER_KEY_PAUSE, ROWHAMMER_KEY_QUIT,
ROWHAMMER_KEY_HOLD (single characters a-z or 0-9, or the words SPACE and
NONE; NONE leaves an action without a letter key). Defaults: a/d rotate
counter-clockwise/clockwise, s soft drop, c hold, p pause, x menu. Moving
left/right (arrow keys), the hard drop (space, arrow up) and holding (w)
always work through their fixed secondary keys as well.

Precedence for every option: command-line argument > environment variable
> config file > built-in default.

Example:
  rowhammer.sh --seed 42 --name Alice --lang de --no-color
EOF
}
