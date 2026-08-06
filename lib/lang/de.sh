#!/usr/bin/env bash
#
# lib/lang/de.sh
#
# Description:
#   German texts for rowhammer (see lib/i18n.sh). Sourced by i18n_init
#   when the resolved language is "de"; it assigns the whole I18N array,
#   so switching the language at runtime cannot leave a stale entry of
#   the previous one behind.
#   German is the language the menus were written in before they became
#   translatable, so this file is the reference the other languages are
#   translated from. ASCII only per the script conventions: umlauts are
#   transcribed (ae, oe, ue, ss), which is what the menus did all along.
#   Entries containing a % are printf format strings and are used with
#   "printf -v" by their caller - the argument order is fixed by the
#   code and must not be rearranged here. Entries holding several lines
#   are read with i18n_lines; every line of a screen text has to stay
#   within the 46 characters the 48-column minimum terminal leaves next
#   to the two-column menu indent, and the lines of the result box
#   within its 18 columns.
#   Library file: sourced by lib/i18n.sh, not meant to be executed directly.
#
# Version: 1.5.1  (2026-08-06)

# Guard: this file is a library and must be sourced, not executed.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    printf 'lib/lang/de.sh is a library; source it from rowhammer.sh\n' >&2
    exit 2
fi

I18N=(
    # --- Menu chrome ------------------------------------------------------
    [menu_any_key]="Beliebige Taste druecken..."
    [menu_nav]="Pfeile/w/s: waehlen   Enter: OK   ESC: zurueck"
    [menu_nav_cancel]="Pfeile/w/s: waehlen  Enter: OK  ESC: abbrechen"
    [menu_more_up]="      ^ %d weitere"
    [menu_more_down]="      v %d weitere"
    [menu_page]="%s (Seite %d/%d)"
    [menu_back]="Zurueck"

    # --- Main menu --------------------------------------------------------
    [main_resume]="Fortsetzen"
    [main_single]="Einzelspieler"
    [main_multi]="Mehrspieler"
    [main_highscores]="Highscores"
    [main_wonders]="Weltwunder"
    [main_stats]="Statistik"
    [main_demos]="Demos"
    [main_settings]="Einstellungen"
    [main_help]="Anleitung"
    [main_quit]="Beenden"
    [mp_body]="Der Mehrspieler-Modus ist noch nicht
verfuegbar. Er folgt in einer spaeteren
Phase (siehe Roadmap)."

    # The state of the running round, shown in every question that would
    # throw it away. Arguments: lines, rows, level.
    [round_state]="%d Lines, %d Rows, Level %d."
    [quit_title]="Wirklich beenden?"
    [quit_yes]="Ja, beenden"
    [confirm_no]="Nein, zurueck"
    [quit_head]="Eine pausierte Runde wartet noch:"
    [quit_tail]="Beim Beenden wird sie gewertet und ist danach
nicht mehr fortsetzbar."

    # --- Game modes -------------------------------------------------------
    # The bare names are used wherever a mode is named on its own (screen
    # titles, the statistics tables, the demo list); the entry_* forms are
    # the bracketed description the three pickers put behind the name.
    # They carry the brackets but no name and no padding: menu_mode_entries
    # (lib/menu.sh) pads every name to the longest one of them, so the
    # descriptions line up in one column whatever a translation calls a
    # mode. Keep them short - name, one space and description have to stay
    # within the 42 characters a menu entry has.
    [mode_marathon]="Marathon"
    [mode_ultra]="Ultra"
    [mode_sprint]="Sprint"
    [mode_timeattack]="Time Attack"
    [mode_timeattack_short]="TimeAtk"
    [mode_flood]="Hochwasser"
    [mode_flood_short]="Flut"
    [entry_marathon]="(endlos, bis Game Over)"
    [entry_ultra]="(%s Rows auf Zeit)"
    [entry_sprint]="(%s Minuten auf Rows)"
    [entry_timeattack]="(%s + %ss je Row)"
    [entry_flood]="(Flut alle %s Sek.)"

    # --- Singleplayer and pause menu --------------------------------------
    [sp_title]="Einzelspieler"
    [pause_title]="Pause"
    [pause_restart]="Neustarten"
    [pause_to_menu]="Ins Hauptmenue (Runde pausiert)"
    [pause_end]="Runde beenden"
    [restart_title]="Wirklich neu starten?"
    [restart_yes]="Ja, neu starten"
    [restart_head]="Die laufende Runde wird aufgegeben:"
    [restart_tail]="Sie wird gewertet (Weltwunder und Statistik)
und danach im selben Modus neu gestartet."
    [end_title]="Runde wirklich beenden?"
    [end_yes]="Ja, beenden"
    [end_head]="Die laufende Runde wird beendet:"
    [end_tail]="Sie wird gewertet und ist danach nicht mehr
fortsetzbar."

    # --- Settings ---------------------------------------------------------
    [set_title]="Einstellungen"
    [set_keys]="Tasten konfigurieren"
    [set_theme]="Farbschema (aktuell: %s)"
    [set_name]="Spielername aendern (aktuell: %s)"
    [set_demo]="Demo-Aufzeichnung (aktuell: %s)"
    [set_lang]="Sprache (aktuell: %s)"
    [on]="an"
    [off]="aus"
    [theme_title]="Farbschema waehlen"
    [theme_guideline]="Guideline"
    [theme_classic]="Classic"
    [theme_mono]="Monochrom"
    [theme_colorblind]="Farbenblind"
    [lang_title]="Sprache waehlen"
    [lang_auto]="Automatisch"

    # --- Key bindings -----------------------------------------------------
    # Keyed by the binding variable, so the settings list and the
    # validation walk the same KEY_ACTIONS table (lib/config.sh).
    [keylabel_KEY_LEFT]="Links"
    [keylabel_KEY_RIGHT]="Rechts"
    [keylabel_KEY_ROT_CW]="Drehen rechts"
    [keylabel_KEY_ROT_CCW]="Drehen links"
    [keylabel_KEY_SOFT]="Soft-Drop"
    [keylabel_KEY_HARD]="Hard-Drop"
    [keylabel_KEY_PAUSE]="Pause"
    [keylabel_KEY_QUIT]="Zurueck ins Menue"
    [keylabel_KEY_HOLD]="Hold"
    [rebind_ask]="Neue Taste fuer \"%s\" druecken"
    [rebind_current]="(aktuell: %s, ESC = abbrechen)"
    [rebind_reserved_menu]="Diese Taste ist fuer die Menuesteuerung
reserviert."
    [rebind_reserved_r]="Die Taste 'r' ist fuer den Neustart im
Game-Over-Bild reserviert."
    [rebind_invalid]="Ungueltige Taste. Erlaubt sind a-z, 0-9
und die Leertaste."
    [rebind_taken]="Die Taste [%s] ist bereits belegt."

    # Key names the game wires in unconditionally, as the manual spells
    # them out next to the configurable binding.
    [key_space]="Leertaste"
    [key_arrow_left]="Pfeil links"
    [key_arrow_right]="Pfeil rechts"
    [key_arrow_down]="Pfeil runter"
    [key_space_up]="Leertaste, Pfeil hoch"
    [key_arrows_lr]="Pfeil links/rechts"

    # --- Text input -------------------------------------------------------
    [input_hint_type]="Tippen ersetzt den markierten Text."
    [input_hint_keys]="Enter: OK   ESC: unveraendert"
    [name_title]="Spielername"
    [name_current]="Aktueller Name: %s"
    [name_rules]="Erlaubt sind max. %d Zeichen aus
A-Z a-z 0-9 Leerzeichen _ -"
    [round_title]="Runde beendet"
    [round_mode]="Modus: %s"
    [round_rows]="Rows: %d   Lines: %d"
    [round_level]="Level: %d   Zeit: %s"
    # Platz in der Bestenliste des Modus: 1 = Rang, 2 = Laenge der Liste.
    # Eine Runde ohne Platz wird seit 1.0.1 gar nicht nach einem Namen
    # gefragt, deshalb gibt es dafuer keinen Text mehr.
    [round_rank]="Bestenliste: Platz %d von %d"
    [round_ask_name]="Name fuer die Bestenliste:"

    # --- Demos ------------------------------------------------------------
    [demos_title]="Demos"
    [demos_title_kept]="Demos (%d)   * = haelt einen Highscore"
    [demos_title_count]="Demos (%d/%d)"
    [demos_none]="Noch keine Aufzeichnungen."
    [demos_none_on]="Jede gespielte Runde wird automatisch
mitgeschnitten und erscheint hier, sobald
sie beendet ist. Es werden die %d
neuesten Runden aufbewahrt."
    [demos_none_off]="Die Demo-Aufzeichnung ist derzeit
ausgeschaltet. Du kannst sie in den
Einstellungen wieder einschalten."
    [demo_title]="Demo"
    [demo_play]="Abspielen"
    [demo_delete]="Loeschen"
    [demo_broken]="(defekt)"
    [demo_busy]="Eine pausierte Runde wartet noch.

Eine Wiedergabe benutzt dasselbe Spielfeld
wie die laufende Runde und wuerde sie
verwerfen. Setze sie fort oder beende sie
ueber das Pausenmenue, dann klappt es."
    [demo_del_title]="Demo loeschen?"
    [demo_del_yes]="Ja, loeschen"
    [demo_del_no]="Nein, behalten"
    [demo_del_hint]="Sie haelt noch einen Highscore-Eintrag."
    [demo_del_body]="Die Aufzeichnung wird wirklich geloescht
und laesst sich nicht zurueckholen."
    [demo_del_failed]="Die Aufzeichnung konnte nicht geloescht
werden:"
    [demo_invalid]="Diese Aufzeichnung ist beschaedigt oder stammt
aus einer anderen Version und kann nicht
abgespielt werden.

Du kannst sie im Demo-Menue loeschen."

    # --- HUD --------------------------------------------------------------
    # The left pane gives a label six columns; anything longer is cut
    # off (pane_stat in lib/render.sh).
    [hud_hold]="Hold"
    [hud_next]="Next"
    [hud_lines]="Reihen"
    [hud_rows]="Rows"
    [hud_level]="Level"
    [hud_gold]="Gold"
    [hud_silver]="Silber"
    [hud_hammer]="Hammer"
    [hud_time]="Zeit"
    [hud_pieces]="Steine"
    [hud_goal]="Ziel"
    [hud_left]="Rest"
    [hud_flood]="Flut"
    [hud_demo]="Demo"

    # --- Result box over the board ----------------------------------------
    # Every line lives inside a box 18 columns wide; the headlines are
    # indented by hand so they sit roughly centered, and the paused line
    # is written out in full for the same reason.
    [box_paused]="     PAUSIERT     "
    [box_game_over]="    GAME OVER"
    [box_ultra_clear]="    ULTRA CLEAR"
    [box_sprint_end]="    SPRINT END"
    [box_time_up]="    ZEIT UM"
    [box_demo_end]="    DEMO ENDE"
    [box_rows]="   Rows %d"
    [box_time]="   Zeit %s"
    [box_rows_goal]="  Rows %d/%d"
    [box_time_goal]="  Zeit %s/%s"
    [box_rank]="  %s #%d"
    [box_rank_marathon]="  Highscore #%d"
    [box_end_over]="  Game Over"
    [box_end_goal]="  Ziel erreicht"
    [box_end_quit]="  Abgebrochen"
    [box_restart]="  r = neu"
    [box_menu]="  %s = Menue"
    [box_demo_again]="  r = nochmal"
    [box_demo_back]="  %s = zurueck"

    # --- Too-small terminal overlay ---------------------------------------
    # Drawn on a terminal that is smaller than the fixed layout, so these
    # four lines have to read correctly in very few columns.
    [resize_head]="Groesse:"
    [resize_need]="brauche %sx%s"
    [resize_now]="jetzt %sx%s"

    # --- World wonders ----------------------------------------------------
    [wonder_all_done]="Alle Weltwunder sind errichtet!"
    [wonder_building]="Weltwunder %d/%d: %s"
    [wonder_finished]="%s ist fertig."
    [wonder_stage]="Baustufe %d/%d - %d/%d Reihen (%d%%)"
    [wonder_total]="Reihen gesamt: %d"
    # Footer of the wonder screen once there is more than one wonder to
    # look at; before that it carries menu_any_key, as it always did.
    [wonder_nav]="Pfeil li/re: Wunder   Enter/ESC: zurueck"
    [wonder_mayan_temple]="Maya-Tempel (Chichen Itza)"
    [wonder_stonehenge]="Stonehenge"
    [wonder_sphinx]="Sphinx von Gizeh"
    [wonder_pantheon]="Pantheon (Rom)"
    [wonder_great_wall]="Chinesische Mauer"
    [wonder_taj_mahal]="Taj Mahal"
    [wonder_st_basils]="Basilius-Kathedrale (Moskau)"

    # --- Highscore lists --------------------------------------------------
    # The column heads are padded to fixed widths by their caller, and
    # the two square labels of the second line have to keep their four
    # characters so the numbers stay in line.
    [hs_title]="Highscores"
    [hs_col_no]="Nr"
    [hs_col_name]="Name"
    [hs_col_rows]="Rows"
    [hs_col_time]="Zeit"
    [hs_col_lines]="Lines"
    [hs_col_date]="Datum"
    [hs_lbl_gold]="Gold"
    [hs_lbl_silver]="Silb"
    # Footer and legend of the list browser (highscore_browse). The
    # footer names the four things the keys do; the legend appears only
    # when at least one entry has a recording.
    [hs_nav]="^v Eintrag  <> Seite  Enter Demo  ESC zurueck"
    [hs_legend_demo]="* = Aufzeichnung vorhanden"
    [hs_no_demo]="Zu diesem Eintrag gibt es keine
Aufzeichnung.

Sie wurde geloescht, war beim Spielen
ausgeschaltet, oder der Eintrag ist aelter
als die Demo-Funktion."
    [hs_empty]="Noch keine Eintraege."
    [hs_empty_marathon]="Spiele eine Runde, um dich einzutragen."
    [hs_empty_ultra]="Erreiche das Ziel von %s Rows in einer
Ultra-Runde, um dich einzutragen. Ein Versuch,
der vorher im Game Over endet, wird nicht
gewertet."
    [hs_empty_sprint]="Spiele eine Sprint-Runde ueber die vollen
%s Minuten, um dich einzutragen. Ein
Versuch, der vorher im Game Over endet, wird
nicht gewertet."
    [hs_empty_timeattack]="Spiele eine Time-Attack-Runde: sie startet
mit %s Minuten Restzeit, und jede Row
bringt eine Sekunde dazu. Gewertet wird
jeder Lauf - auch ein vorzeitiges Game Over."
    [hs_empty_flood]="Spiele eine Hochwasser-Runde: alle %s
Sekunden schiebt sich eine Reihe von unten
ins Feld. Gewertet wird jede Runde - sie
endet ohnehin immer im Game Over."

    # --- Statistics -------------------------------------------------------
    [stats_title]="Statistik"
    [stats_all]="Gesamt (alle Modi)"
    [stats_lines]="Abgebaute Reihen:"
    [stats_bonus]="Bonusreihen:"
    # Verhaeltnis der beiden Zeilen darueber, Wert "1:X.XX" (eine
    # abgebaute Reihe zu so vielen Bonusreihen). Label hoechstens 26
    # Zeichen wie die uebrigen Zaehler-Beschriftungen.
    [stats_ratio]="Verhaeltnis Reihen/Bonus:"
    [stats_total]="Reihen gesamt (gewertet):"
    [stats_gold]="Goldbloecke:"
    [stats_silver]="Silberbloecke:"
    [stats_hammer]="Rowhammer (4 Reihen):"
    [stats_pieces]="Abgelegte Steine:"
    [stats_playtime]="Spielzeit gesamt:"
    [stats_ppm]="Steine/Minute (PCS/min):"
    [stats_recent_head]="Letzte Spiele (neueste zuerst):"
    [stats_recent_none]="Noch keine Spiele."
    [stats_recent_rows]="Rows"
    [stats_recent_lines]="Reihen"
    [stats_recent_bonus]="Bonus"
    # Dritte Zeile eines Eintrags der letzten Spiele, vor dem Wert
    # "1:X.XX"; die beiden Zeilen darueber sind voll (44 von 46 Zeichen).
    [stats_recent_ratio]="Reihen/Bonus"
    [stats_modes_head]="Runden je Spielmodus:"
    [stats_rounds]="Runden:"
    [stats_rounds_total]="Runden gesamt:"
    [stats_rows_per_round]="Rows je Runde:"
    [stats_goal_rate]="Erfolgsquote:"
    [stats_goal_ultra]="davon Ziel erreicht:"
    [stats_goal_sprint]="davon volle Zeit:"
    [stats_goal_timeattack]="davon Zeit abgelaufen:"

    # --- Manual -----------------------------------------------------------
    [help_title]="Anleitung"
    [help_nav]="Pfeil li/re: Seite   Enter/ESC: zurueck"
    [help_p0]="rowhammer ist ein Tetris-Spiel fuers Terminal,
Vorbild ist \"The New Tetris\" (N64).

Bausteine muessen so gestapelt werden, dass
sich Reihen komplett fuellen: volle Reihen
werden abgebaut und als \"Rows\" gewertet -
das ist zugleich der Punktestand der Runde.

Die Steine kommen aus einem 7er-Beutel: Jede
der sieben Sorten genau einmal, dann wird
neu gemischt.

Mit jeder abgebauten Reihe steigt das Level,
und die Steine fallen schneller. Ist kein
Platz mehr fuer einen neuen Stein, ist die
Runde vorbei."
    [help_p1_head]="Steuerung im Spiel (die Buchstabentasten
sind unter Einstellungen aenderbar):
"
    [help_key_left]="Nach links"
    [help_key_right]="Nach rechts"
    [help_key_rot_cw]="Drehen rechts"
    [help_key_rot_ccw]="Drehen links"
    [help_key_soft]="Soft-Drop"
    [help_key_hard]="Hard-Drop"
    [help_key_hold]="Hold / Tauschen"
    [help_key_pause]="Pause"
    [help_key_quit]="Pausenmenue"
    [help_p1_tail]="
Soft-Drop laesst den Stein schneller fallen,
Hard-Drop setzt ihn sofort fest.
Neustart: [r] im Game Over oder Pausenmenue.
In den Menues: Pfeile oder w/s waehlen,
Enter bestaetigt, ESC geht zurueck."
    # Argument: the key(s) that hold a piece.
    [help_p2]="Vorschau und Hold

Oben rechts (\"Next\") stehen die naechsten
drei Steine - genug Vorlauf, um den Stapel
zu planen.

Links oben liegt der Hold-Speicher. Mit
%s wandert der aktuelle Stein dorthin;
liegt dort schon einer, tauschen die beiden
die Plaetze und der geholdete Stein faellt
in seiner Startlage neu ein.

Pro Zug ist nur ein Tausch erlaubt - erst
nach dem naechsten Ablegen kann erneut
getauscht werden. So laesst sich ein I-Stein
fuer den grossen Abbau aufheben oder ein
unpassendes Teil kurz parken."
    [help_p3_head]="Vier vollstaendige, unversehrte Steine, die
zusammen ein 4x4-Quadrat exakt ausfuellen,
werden zu einem Bonusblock:
"
    [help_sq_gold]="Gold"
    [help_sq_gold_text]="alle vier Steine gleicher Sorte"
    [help_sq_silver]="Silber"
    [help_sq_silver_text]="vier gemischte Sorten"
    [help_p3_mid]="
Ein Stein, den ein Reihenabbau bereits
zerschnitten hat, zaehlt nicht mehr mit.

Beim Abbau einer Reihe zaehlt (in Rows):"
    [help_row_base]="Grundwert je Reihe"
    [help_row_silver]="je Silber-Quadrat in der Reihe"
    [help_row_gold]="je Gold-Quadrat in der Reihe"
    [help_row_hammer]="Rowhammer (4 Reihen auf einmal)"
    [help_p3_tail]="
Ein Rowhammer quer durch zwei komplette
Gold-Quadrate bringt so 4+1+80 = 85 Rows."
    [help_p4_head]="Alle abgebauten Reihen zaehlen ueber die
Runden hinweg zusammen (auch die einer
abgebrochenen Runde) und bauen nacheinander
sieben Weltwunder auf.

Gewertete Reihen je Weltwunder:"
    [help_p4_tail]="
\"Weltwunder\" zeigt die Baustelle: sie waechst
von unten und steht bei 100 Prozent fertig -
ebenso nach jeder Runde. Pfeil links/rechts
blaettert zurueck zu den fertigen Wundern."
    [help_p5_head]="Spielmodi (Menuepunkt \"Einzelspieler\"):

Marathon - die endlose Runde. Sie endet,
  wenn kein neuer Stein mehr Platz hat.
"
    [help_p5_ultra]="Ultra - %s Rows so schnell wie moeglich.
  Ergebnis ist die Spielzeit; die Runde
  endet, sobald das Ziel erreicht ist.
"
    [help_p5_sprint]="Sprint - in %s Minuten so viele Rows
  wie moeglich. Ergebnis sind die Rows;
  die Runde endet mit Ablauf der Zeit.
"
    [help_p6_head]="Spielmodi (Fortsetzung):
"
    [help_p6_timeattack]="Time Attack - %s Minuten Restzeit, die
  rueckwaerts laeuft; jede Row bringt %s Sek.
  dazu. Ergebnis sind die Rows; die Runde
  endet bei 00:00 - oder frueher im Game Over.
"
    [help_p6_flood]="Hochwasser - alle %s Sekunden schiebt
  sich von unten eine Reihe mit einem Loch
  ins Feld und das Feld rueckt nach oben.
  Sonst wie Marathon: Ergebnis sind die Rows,
  die Runde endet oben."
    [help_p7]="Bestenlisten (Menuepunkt \"Highscores\"):

Jeder Modus hat eine eigene Liste. Alle
ranken nach Rows, nur Ultra nach der
kuerzesten Zeit.

Bei Ultra und Sprint zaehlt nur ein Lauf, der
sein Ziel bzw. die volle Zeit erreicht hat -
ein Game Over davor wird nicht gewertet.

Bei Time Attack und Hochwasser zaehlt dagegen
jede Runde: die Rows sind so oder so dieselbe
Leistung, und wer vorzeitig oben rausbaut,
hat schlicht weniger davon.

Reihen und Zaehler einer abgebrochenen Runde
fliessen immer in Weltwunder und Statistik
ein."
    [help_p8_head]="Demos (Menuepunkt \"Demos\"):

Jede gespielte Runde wird mitgeschnitten und
kann spaeter noch einmal angesehen werden.
Aufgezeichnet werden die Zuege, nicht das
Bild - die Wiedergabe spielt die Runde neu.
"
    [help_p8_kept]="Aufbewahrt werden die %d neuesten Runden;"
    [help_p8_mid]="Aufnahmen mit * halten noch einen Highscore
und bleiben darueber hinaus erhalten.
Einzelne loeschen kannst du im Demo-Menue,
die Aufzeichnung in den Einstellungen.
Die Highscore-Liste spielt sie mit Enter ab.

Waehrend der Wiedergabe:"
    [help_demo_pause]="Pause / weiter"
    [help_demo_speed]="Tempo"
    [help_demo_back]="Zurueck"

    # --- One-time rename of the Marathon highscore file (0.51.0) ----------
    # Printed before the terminal is touched, like the reset dialog.
    # Arguments: old path, new path.
    [highscore_renamed]="Bestenliste umbenannt: %s -> %s"

    # --- Reset dialog (runs before the terminal is touched) ---------------
    [reset_affects]="Reset \"%s\" betrifft diese Dateien in %s:"
    [reset_absent]="(nicht vorhanden)"
    [reset_note]="Sie werden nicht geloescht, sondern nach <datei>-YYYYMMDDhhmmss.bak verschoben."
    [reset_confirm]="Bist du sicher, dass du %s zuruecksetzen moechtest? [N/y] "
    [reset_aborted]="Reset abgebrochen, es wurde nichts verschoben."
    [reset_wait]="Backup aus derselben Sekunde vorhanden, warte auf die naechste..."
    [reset_moved]="Verschoben: %s -> %s"
    [reset_done]="Reset erfolgreich"
    [reset_summary]="Reset \"%s\": %d Datei(en) gesichert, %d nicht vorhanden."
)

# i18n_usage_text
# The --help output in this language. A function with a quoted heredoc
# rather than an I18N entry: the text is long, holds quotes and percent
# signs, and is printed exactly once - nothing here needs to survive as
# a variable. Only the language file loaded by i18n_init defines it, so
# the languages cannot collide over the name.
i18n_usage_text() {
    cat <<'EOF'
Aufruf: rowhammer.sh [OPTIONEN]

Terminal-Tetris des rowhammer-Projekts. Startet mit einem Menue:
Einzelspieler (endloser "Marathon", die Zeitmodi "Ultra", "Sprint" und
"Time Attack" sowie "Hochwasser"), Mehrspieler (Platzhalter), Highscores,
Weltwunder, Statistik, Demos und Einstellungen.

Optionen:
  --seed N      Startwert des Zufallsgenerators fuer eine
                reproduzierbare Steinfolge.
                Env: ROWHAMMER_SEED         Standard: (zufaellig)
  --name NAME   Spielername, unter dem Highscore-Eintraege gespeichert
                werden (max. 16 Zeichen aus A-Z a-z 0-9 Leerzeichen _ -).
                Env: ROWHAMMER_PLAYER_NAME  Standard: Player
  --lang CODE   Sprache der Oberflaeche: "de" (Deutsch), "en"
                (Englisch) oder "auto". "auto" nimmt die Sprache aus
                den Locale-Variablen (LC_ALL, LC_MESSAGES, LANG) und
                faellt auf Deutsch zurueck, wenn dort keine der
                unterstuetzten Sprachen steht. Auch im
                Einstellungsmenue waehlbar und dort gespeichert.
                Env: ROWHAMMER_LANG         Standard: auto
  --data-dir DIR
                Verzeichnis fuer alle dauerhaften Spieldaten: die
                Konfigurationsdatei rowhammer.conf, die Bestenlisten,
                den Spielstand, die Statistik und die Demos.
                Env: ROWHAMMER_DATA_DIR     Standard: ~/.config/rowhammer
  --no-color    ANSI-Farben abschalten. Jede Steinsorte wird dann mit
                einem eigenen Zwei-Zeichen-Glyph gezeichnet (II OO TT SS
                ZZ JJ LL), damit abgelegte Steine unterscheidbar
                bleiben; Gold-Quadrate erscheinen als "##", Silber als
                "%%". Hat Vorrang vor --color-mode. Die
                De-facto-Standardvariable NO_COLOR
                (https://no-color.org/) wird ebenfalls beachtet: ist sie
                gesetzt und nicht leer, sind Farben standardmaessig aus;
                mit ROWHAMMER_NO_COLOR=0 lassen sie sich wieder
                einschalten.
                Env: ROWHAMMER_NO_COLOR     Standard: 0
  --color-mode MODUS
                Farbpalette: "auto" erkennt 256-Farben-Unterstuetzung
                (tput colors, TERM, COLORTERM) und waehlt danach
                extended oder basic; "basic" erzwingt die
                8/16-Farben-Palette; "extended" erzwingt die
                xterm-256-Farben-Palette.
                Env: ROWHAMMER_COLOR_MODE   Standard: auto
  --color-theme NAME
                Farbschema fuer Steine und Gold-/Silber-Quadrate:
                "guideline" (Standard), "classic", "mono" oder
                "colorblind". Auch im Einstellungsmenue waehlbar und
                dort gespeichert.
                Env: ROWHAMMER_COLOR_THEME  Standard: guideline
  --demo-record on|off
                Jede Runde als Demo mitschneiden, die sich ueber den
                Menuepunkt "Demos" ansehen laesst (siehe unten). Auch im
                Einstellungsmenue umschaltbar und dort gespeichert.
                Env: ROWHAMMER_DEMO_RECORD  Standard: on
  --render-mode MODUS
                Wie der Spielbildschirm ans Terminal geht: "partial"
                schreibt nur die seit dem letzten Bild geaenderten
                Zeilen (Standard - rund die Haelfte der Zeit und ein
                Vierzehntel der Ausgabe eines Vollbilds); "full"
                schreibt je Bild den ganzen 48x22-Block, wie der
                Renderer es vor 0.22.0 tat. "full" ist der Rueckfall
                fuer Terminals und Multiplexer, die das inkrementelle
                Update falsch darstellen, und fuer ein Frame-Log mit
                ganzen Bildern.
                Env: ROWHAMMER_RENDER_MODE  Standard: partial
  --reset ZIEL  Dauerhafte Daten im Datenverzeichnis zuruecksetzen und
                beenden, ohne das Spiel zu starten. ZIEL ist eines von:
                  config     die Konfigurationsdatei rowhammer.conf
                  stats      die Statistikdatei stats
                  highscore  alle Bestenlisten (highscore-marathon,
                             highscore-ultra, highscore-sprint,
                             highscore-timeattack und highscore-flood)
                  save       der Spielstand save (Weltwunder-Fortschritt)
                  demo       die Demo-Aufzeichnungen (Verzeichnis demos)
                  all        alles davon
                Geloescht wird nichts: jede betroffene Datei wandert
                nach <datei>-YYYYMMDDhhmmss.bak daneben, ein Reset
                laesst sich also durch Zurueckschieben rueckgaengig
                machen. Laeuft derselbe Reset zweimal in einer Sekunde,
                wird auf die naechste Sekunde gewartet, statt das eben
                geschriebene Backup zu ueberschreiben.
                An einem Terminal werden die betroffenen Dateien erst
                aufgelistet und der Reset bestaetigt ([N/y], die
                Vorgabe ist nein); ohne Terminal (Skript, CI) laeuft er
                sofort, weil eine wartende Abfrage den Aufrufer haengen
                liesse. Nicht vorhandene Dateien sind kein Fehler.
                Env: ROWHAMMER_RESET        Standard: (kein Reset)
  --force       Sicherheitsabfragen automatisch mit "ja" beantworten.
                Mit jeder anderen Option kombinierbar; ausserhalb der
                Menues wird derzeit nur beim Reset gefragt, "--reset all
                --force" laeuft also ohne Rueckfrage.
                Env: ROWHAMMER_FORCE        Standard: 0
  --debug       Debug-/Trace-Modus: die Sitzung wird in Log-Dateien
                mitgeschrieben (siehe unten). Die Logs koennen in langen
                Sitzungen mehrere Megabyte gross werden.
                Env: ROWHAMMER_DEBUG        Standard: 0
  --debug-dir DIR
                Verzeichnis fuer die Debug-Logs dieses Laufs.
                Env: ROWHAMMER_DEBUG_DIR
                Standard: ~/.local/state/rowhammer/debug/<zeit>.<pid>
  -h, --help    Diese Hilfe anzeigen und beenden.

Der Debug-Modus schreibt drei zusammengehoerige Log-Dateien (gemeinsame
Millisekunden-Zeitstempel und ein Bildschirm-Update-Zaehler), damit
Fehlerberichte nachvollziehbar werden:
  events.log    Sitzungskopf (Version, Terminal, Seed, Tastenbelegung,
                Konfigurationsdateien) und jede Spielaktion: Spawns,
                Bewegungen und Drehungen (auch blockierte), Faelle,
                Locks, Quadrat-Bildung, Reihenabbau mit Aufschluesselung
                der Wertung, Hold, Pause, Menuewahl, gespeicherte
                Einstellungen und ein Board-Abbild nach jedem Lock.
  input.log     jeder Tastendruck mit Rohbytes und gemapptem Symbol.
  frames.log    jede Bildschirmausgabe Byte fuer Byte (1:1, ANSI
                inklusive).
Das Log-Verzeichnis wird beim Beenden ausgegeben.

Steuerung (Standardbelegung). Die Buchstabentaste jeder Aktion ist im
Einstellungsmenue aenderbar; die daneben genannten Pfeiltasten, die
Leertaste und w liegen fest darueber und funktionieren immer:
  Pfeil links / rechts        Stein bewegen (ohne Buchstabentaste)
  d                           im Uhrzeigersinn drehen
  a                           gegen den Uhrzeigersinn drehen
  s oder Pfeil runter         Soft-Drop
  Leertaste oder Pfeil hoch   Hard-Drop (ohne Buchstabentaste)
  c oder w                    Hold / Stein tauschen (einmal je Zug)
  p                           Pause / weiter
  x oder ESC                  Pausenmenue: fortsetzen, Runde im selben
                              Modus neu starten, ins Hauptmenue mit
                              pausierter Runde (ueber "Fortsetzen"
                              wieder aufnehmbar) oder Runde beenden
  r                           Neustart (im Game-Over-Bild)

Quadrat-Mechanik (The New Tetris): Vier vollstaendige, unversehrte
Steine, die ein 4x4-Feld exakt ausfuellen, werden zu einem Quadrat -
Gold, wenn alle vier dieselbe Sorte haben, sonst Silber. Jede abgebaute
Reihe zaehlt 1 Reihe Wertung, dazu 10 je Gold- und 5 je Silber-Quadrat,
durch das sie laeuft (additiv); vier Reihen auf einmal (ein Tetris)
bringen 1 zusaetzlich. Die Wertung steht im HUD als "Rows" und ist der
einzige Punktestand des Spiels: nur abgebaute Reihen zaehlen, Drops,
Quadrat-Bildung und Spins bringen nichts. Beruehmtes Maximum fuer einen
Zug: ein Tetris durch zwei komplette Gold-Quadrate = 4 + 1 + 8 x 10 = 85.

Spielmodi (Menuepunkt "Einzelspieler"): "Marathon" ist die endlose
Runde, die im Game Over endet. "Ultra" ist ein Wettlauf - 150 Rows so
schnell wie moeglich; die Runde endet, sobald das Ziel erreicht ist, und
das Ergebnis ist die Spielzeit. "Sprint" ist das Spiegelbild - in 3
Minuten Spielzeit so viele Rows wie moeglich; die Runde endet mit Ablauf
der Zeit. "Time Attack" macht die Uhr zum Einsatz: die Runde startet mit
1 Minute Restzeit, die rueckwaerts laeuft, und jede gewertete Row bringt
1 Sekunde zurueck - der Lauf dauert also genau so lange, wie er sich
selbst am Leben haelt, und endet bei 00:00 (oder vorher im Game Over);
Ergebnis sind die Rows. "Hochwasser" ist Marathon mit steigendem Wasser:
alle 20 Sekunden Spielzeit schiebt sich von unten eine volle Reihe mit
genau einem Loch ins Feld, das Feld rueckt dabei nach oben, und die Runde
endet, wenn der Stapel oben ankommt; Ergebnis sind auch hier die Rows.
Das HUD zeigt waehrend eines Laufs das Ziel und
was davon noch fehlt bzw. wann die naechste Flutreihe kommt. Jeder Modus
hat eine eigene Bestenliste - Ultra
nach Zeit (<data-dir>/highscore-ultra, schnellster Lauf zuerst), Sprint,
Time Attack und Hochwasser nach Rows (<data-dir>/highscore-sprint,
<data-dir>/highscore-timeattack, <data-dir>/highscore-flood) -, sodass
sie die Top Ten der endlosen
Liste nie verdraengen. Bei Ultra und Sprint wird nur ein Lauf gewertet,
der sein Ziel erreicht hat; seine Reihen zaehlen wie bei jeder
abgebrochenen Runde trotzdem fuer Weltwunder und Statistik. Jede
Time-Attack- und jede Hochwasser-Runde wird dagegen gewertet: ihre Rows
sind dieselbe Leistung, ob die Uhr, das Wasser oder der Stapel sie
beendet hat. Der Menuepunkt
"Highscores" fragt, welche der fuenf Listen gezeigt werden soll.

Weltwunder: Die Reihenwertung jeder Runde wird auf einen dauerhaften
Zaehler in <data-dir>/save addiert. Er baut nacheinander sieben
Weltwunder auf; die aktuelle Baustelle (ASCII-Art, die von unten
aufgedeckt wird) erscheint nach jeder Runde und ueber den Menuepunkt
"Weltwunder".

Demos: Jede Runde wird mitgeschnitten und laesst sich ueber den
Menuepunkt "Demos" noch einmal ansehen; er listet die Aufzeichnungen mit
Datum, Modus, Spielzeit und Rows und bietet Abspielen oder Loeschen an.
Aufgezeichnet werden die Zuege, die Gravitationsschritte und die
Steinfolge der Runde - nicht der Bildschirm -, sodass die Wiedergabe die
Runde wirklich noch einmal spielt: das kostet rund 2 kB je Spielminute,
ist unabhaengig von Terminalgroesse, Farben und Render-Modus beider
Sitzungen und dauert so lange wie die Runde. Waehrend einer Wiedergabe
haelt die Pausetaste (oder die Leertaste) an, die Pfeiltasten links und
rechts stellen das Tempo zwischen 0.25x und 4x, und die Quit-Taste
kehrt zur Liste zurueck; "r" spielt eine durchgelaufene Demo noch einmal
ab. Die Aufnahmen liegen in <data-dir>/demos, die zehn neuesten werden
aufbewahrt, und die laufende Runde wird auf eine RAM-Disk geschrieben
(XDG_RUNTIME_DIR bzw. /dev/shm), sodass das Spielen keine
Schreibzugriffe auf die Platte kostet. Mitschneiden laesst sich mit
--demo-record off oder im Einstellungsmenue abschalten; eine Wiedergabe
kommt nie in die Bestenlisten, den Weltwunder-Fortschritt oder die
Statistik.

Statistik: Jede beendete Runde addiert ihre abgebauten Reihen, die
Bonusreihen (der Gold-/Silber-/Tetris-Anteil der Wertung) und die
gebauten Gold- und Silberquadrate auf dauerhafte Gesamtzaehler in
<data-dir>/stats; die Ergebnisse der letzten drei Runden und die Zahl
der Runden je Spielmodus - samt der Laeufe, die ihr Ziel erreicht haben
- stehen ebenfalls dort. Jeder Zaehler wird zusaetzlich je Modus
gefuehrt, sodass sich dieselben Zahlen fuer Marathon, Ultra, Sprint,
Time Attack oder Hochwasser allein lesen lassen; die Gesamtzaehler
bleiben, was sie immer waren, und werden nicht aus den Modus-Zaehlern
summiert. Der Menuepunkt "Statistik" fragt, welche der beiden Sichten
gezeigt werden soll.

Die Einstellungen (Spielername, Sprache, Farbschema, Tastenbelegung,
Demo-Aufzeichnung) liegen in der Konfigurationsdatei
<data-dir>/rowhammer.conf, standardmaessig
~/.config/rowhammer/rowhammer.conf. Die Tastenbelegung laesst sich
zusaetzlich ueber die Umgebungsvariablen ROWHAMMER_KEY_LEFT,
ROWHAMMER_KEY_RIGHT, ROWHAMMER_KEY_ROT_CW, ROWHAMMER_KEY_ROT_CCW,
ROWHAMMER_KEY_SOFT, ROWHAMMER_KEY_HARD, ROWHAMMER_KEY_PAUSE,
ROWHAMMER_KEY_QUIT und ROWHAMMER_KEY_HOLD setzen (einzelne Zeichen a-z
oder 0-9 oder die Woerter SPACE und NONE; NONE laesst eine Aktion ohne
Buchstabentaste).

Praezedenz jeder Option: Kommandozeile > Umgebungsvariable >
Konfigurationsdatei > eingebauter Standard.

Beispiel:
  rowhammer.sh --seed 42 --name Alice --lang en --no-color
EOF
}
