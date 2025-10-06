{
  config,
  lib,
  pkgs,
  ...
}: {
  config = lib.mkIf (config.desktops.hyprland.enable or false) {
    home.packages = with pkgs; [
      # Required for mediaplayer.py
      python3
      python3Packages.pygobject3
      python3Packages.dbus-python
      playerctl
      gobject-introspection
    ];

    home.file = {
      ".config/waybar/scripts/spotify.sh" = {
        executable = true;
        text = ''
          #!/usr/bin/env bash
          player_status=$(playerctl -p spotify status 2> /dev/null)
          if [ "$player_status" = "Playing" ]; then
              echo "$(playerctl -p spotify metadata artist) - $(playerctl -p spotify metadata title)"
          elif [ "$player_status" = "Paused" ]; then
              echo " $(playerctl -p spotify metadata artist) - $(playerctl -p spotify metadata title)"
          else
              echo ""
          fi
        '';
      };

      ".config/waybar/scripts/weather.sh" = {
        executable = true;
        text = ''
          #!/usr/bin/env bash

          # Cache file location
          CACHE_FILE="$HOME/.cache/waybar_weather"
          CACHE_MAX_AGE=1800  # 30 minutes in seconds

          # Function to output cached data
          output_cached() {
            if [ -f "$CACHE_FILE" ]; then
              cat "$CACHE_FILE"
            else
              echo '{"text":"Weather unavailable","tooltip":"No cached data available","class":"weather-error"}'
            fi
          }

          # Check if cache is valid (exists and not too old)
          if [ -f "$CACHE_FILE" ]; then
            cache_age=$(($(date +%s) - $(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)))
            if [ $cache_age -lt $CACHE_MAX_AGE ]; then
              # Cache is still valid, use it
              output_cached
              exit 0
            fi
          fi

          # Try to get fresh weather data with timeout
          weather_full=$(timeout 10 curl -s 'https://wttr.in' 2>/dev/null)

          if [ -n "$weather_full" ]; then
            # Parse the main weather info from the full report
            # Remove ANSI color codes and extract data
            clean_weather=$(echo "$weather_full" | sed 's/\[[0-9;]*m//g')

            # Extract location from the first line
            location=$(echo "$clean_weather" | head -1 | sed 's/Weather report: //' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')

            # Extract temperature from the main display (line with temperature)
            temp=$(echo "$clean_weather" | head -6 | grep -oE '\+[0-9]+' | head -1)

            # Extract weather condition (Sunny, Cloudy, etc.)
            condition=$(echo "$clean_weather" | head -6 | grep -oE '(Sunny|Cloudy|Rainy|Clear|Overcast|Partly cloudy|Light rain|Heavy rain|Snow|Foggy|Thunderstorm)' | head -1)

            # Extract wind info
            wind=$(echo "$clean_weather" | head -6 | grep -oE '[↑↓↗↖↘↙→←][[:space:]]*[0-9]+[[:space:]]*mph' | head -1 | tr -d ' ')

            # Extract humidity from detailed forecast if available
            humidity=$(echo "$clean_weather" | grep -oE '[0-9]+%' | head -1)

            # Extract precipitation amount and chance
            precip_line=$(echo "$clean_weather" | head -8 | grep -oE '[0-9]+\.[0-9]+ in' | head -1)
            precip_chance=$(echo "$clean_weather" | grep -oE '[0-9]+% ' | head -1 | tr -d ' ')

            # If no precipitation amount found, try to get it from the main weather display
            if [ -z "$precip_line" ]; then
              precip_line=$(echo "$clean_weather" | head -8 | grep -oE '[0-9]+\.[0-9]+ mm' | head -1)
            fi

            # Get weather icon (try to extract emoji from original)
            icon=$(echo "$weather_full" | head -6 | grep -oE '[☀️🌤️⛅🌦️🌧️⛈️🌩️🌨️❄️🌫️]' | head -1)

            # Fallback icons based on condition
            if [ -z "$icon" ]; then
              case "$condition" in
                "Sunny"|"Clear") icon="☀️" ;;
                "Cloudy"|"Overcast") icon="☁️" ;;
                "Partly cloudy") icon="⛅" ;;
                "Rainy"|"Light rain") icon="🌧️" ;;
                "Heavy rain") icon="⛈️" ;;
                "Snow") icon="❄️" ;;
                "Foggy") icon="🌫️" ;;
                *) icon="🌡️" ;;
              esac
            fi

            # Build display text
            if [ -n "$temp" ] && [ -n "$condition" ]; then
              weather_simple="$icon ''${temp}°F"

              # Build detailed tooltip
              tooltip_parts=()
              [ -n "$location" ] && tooltip_parts+=("$location")
              [ -n "$condition" ] && tooltip_parts+=("$condition")
              [ -n "$temp" ] && tooltip_parts+=("Temperature: ''${temp}°F")
              [ -n "$wind" ] && tooltip_parts+=("Wind: $wind")
              [ -n "$humidity" ] && tooltip_parts+=("Humidity: $humidity")
              [ -n "$precip_line" ] && tooltip_parts+=("Precipitation: $precip_line")
              [ -n "$precip_chance" ] && tooltip_parts+=("Rain chance: $precip_chance")

              # Join tooltip parts with newlines
              weather_details=""
              for part in "''${tooltip_parts[@]}"; do
                if [ -z "$weather_details" ]; then
                  weather_details="$part"
                else
                  weather_details="$weather_details\\n$part"
                fi
              done

              result="{\"text\":\"$weather_simple\",\"tooltip\":\"$weather_details\",\"class\":\"weather\"}"

              # Save successful result to cache
              mkdir -p "$(dirname "$CACHE_FILE")"
              echo "$result" > "$CACHE_FILE"
              echo "$result"
            else
              # Parsing failed, try to use cached data
              output_cached
            fi
          else
            # Fetch failed, try to use cached data
            output_cached
          fi
        '';
      };

      ".config/waybar/scripts/screenshot_full" = {
        executable = true;
        text = ''
          #!/usr/bin/env bash
          grimblast copy output
          notify-send "Screenshot" "Full screen captured to clipboard"
        '';
      };

      ".config/waybar/scripts/screenshot_area" = {
        executable = true;
        text = ''
          #!/usr/bin/env bash
          grimblast copy area
          notify-send "Screenshot" "Area captured to clipboard"
        '';
      };

      ".config/waybar/mediaplayer.py" = {
        executable = true;
        text = ''
          #!/usr/bin/env python3
          import argparse
          import logging
          import sys
          import signal
          import gi
          import json
          gi.require_version('Playerctl', '2.0')
          from gi.repository import Playerctl, GLib

          logger = logging.getLogger(__name__)

          def write_output(text, player):
              logger.info('Writing output')
              output = {'text': text,
                        'class': 'custom-' + player.props.player_name,
                        'alt': player.props.player_name}
              sys.stdout.write(json.dumps(output) + '\n')
              sys.stdout.flush()

          def on_play(player, status, manager):
              logger.info('Received new playback status')
              on_metadata(player, player.props.metadata, manager)

          def on_metadata(player, metadata, manager):
              logger.info('Received new metadata')
              track_info = ""

              if player.props.player_name == 'spotify' and \
                      'mpris:trackid' in metadata.keys() and \
                      ':ad:' in player.props.metadata['mpris:trackid']:
                  track_info = 'AD PLAYING'
              elif player.get_artist() != "" and player.get_title() != "":
                  track_info = '{artist} - {title}'.format(artist=player.get_artist(),
                                                           title=player.get_title())
              else:
                  track_info = player.get_title()

              if player.props.status != 'Playing' and track_info:
                  track_info = ' ' + track_info
              write_output(track_info, player)

          def on_player_appeared(manager, player, selected_player=None):
              if player is not None and (selected_player is None or player.name == selected_player):
                  init_player(manager, player)
              else:
                  logger.debug("New player appeared, but it's not the selected player, skipping")

          def on_player_vanished(manager, player):
              logger.info('Player has vanished')
              sys.stdout.write('\n')
              sys.stdout.flush()

          def init_player(manager, name):
              logger.debug('Initialize player: {player}'.format(player=name.name))
              player = Playerctl.Player.new_from_name(name)
              player.connect('playback-status', on_play, manager)
              player.connect('metadata', on_metadata, manager)
              manager.manage_player(player)
              on_metadata(player, player.props.metadata, manager)

          def signal_handler(sig, frame):
              logger.debug('Received signal to stop, exiting')
              sys.stdout.write('\n')
              sys.stdout.flush()
              sys.exit(0)

          def parse_arguments():
              parser = argparse.ArgumentParser()
              parser.add_argument('-v', '--verbose', action='count', default=0)
              parser.add_argument('--player')
              return parser.parse_args()

          def main():
              arguments = parse_arguments()
              logging.basicConfig(stream=sys.stderr, level=logging.DEBUG,
                                  format='%(name)s %(levelname)s %(message)s')
              logger.setLevel(max((3 - arguments.verbose) * 10, 0))
              logger.debug('Arguments received {}'.format(vars(arguments)))

              manager = Playerctl.PlayerManager()
              loop = GLib.MainLoop()

              manager.connect('name-appeared', lambda *args: on_player_appeared(*args, arguments.player))
              manager.connect('player-vanished', on_player_vanished)

              signal.signal(signal.SIGINT, signal_handler)
              signal.signal(signal.SIGTERM, signal_handler)

              for player in manager.props.player_names:
                  if arguments.player is not None and arguments.player != player.name:
                      logger.debug('{player} is not the filtered player, skipping it'
                                   .format(player=player.name))
                      continue
                  init_player(manager, player)

              loop.run()

          if __name__ == '__main__':
              main()
        '';
      };

      # Note: mail.py requires a mailsecrets.py file with credentials
      # This is a template - user needs to create mailsecrets.py separately
      ".config/waybar/modules/mail.py" = {
        executable = true;
        text = ''
          #!/usr/bin/env python3
          import os
          import imaplib

          # Create a mailsecrets.py file with:
          # username = "your-email@example.com"
          # password = "your-password"
          # server = "imap.example.com"

          try:
              import mailsecrets
          except ImportError:
              print('{"text":"", "alt": ""}')
              exit(1)

          def getmails(username, password, server):
              imap = imaplib.IMAP4_SSL(server, 993)
              imap.login(username, password)
              imap.select('INBOX')
              ustatus, uresponse = imap.uid('search', None, 'UNSEEN')
              if ustatus == 'OK':
                  unread_msg_nums = uresponse[0].split()
              else:
                  unread_msg_nums = []

              fstatus, fresponse = imap.uid('search', None, 'FLAGGED')
              if fstatus == 'OK':
                  flagged_msg_nums = fresponse[0].split()
              else:
                  flagged_msg_nums = []

              return [len(unread_msg_nums), len(flagged_msg_nums)]

          ping = os.system("ping " + mailsecrets.server + " -c1 > /dev/null 2>&1")
          if ping == 0:
              mails = getmails(mailsecrets.username, mailsecrets.password, mailsecrets.server)
              text = ""
              alt = ""

              if mails[0] > 0:
                  text = alt = str(mails[0])
                  if mails[1] > 0:
                      alt = str(mails[1]) + "  " + alt
              else:
                  exit(1)

              print('{"text":"' + text + '", "alt": "' + alt + '"}')
          else:
              exit(1)
        '';
      };

      ".config/waybar/waybar.sh" = {
        executable = true;
        text = ''
          #!/usr/bin/env bash
          # Waybar launcher script
          CONFIG_FILES="$HOME/.config/waybar/config $HOME/.config/waybar/style.css"

          trap "killall waybar" EXIT

          while true; do
              waybar &
              inotifywait -e create,modify $CONFIG_FILES
              killall waybar
          done
        '';
      };
    };
  };
}
