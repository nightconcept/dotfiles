{
  config,
  lib,
  pkgs,
  ...
}: {
  config = lib.mkIf (config.desktops.hyprland.enable or false) {
    programs.waybar.style = ''
      * {
          font-family: "InterVariable Nerd Font", "Inter", "FiraCode Nerd Font Propo", Roboto, Helvetica, Arial, sans-serif;
          font-size: 18px;
          font-weight: 800;
          margin: 0;
          padding: 0;
          transition-property: background-color;
          transition-duration: 0.5s;
      }

      * {
          border: none;
          border-radius: 3px;
          min-height: 0;
          margin: 0.1em 0.2em 0.1em 0.2em;
      }

      #waybar {
          background-color: rgba(26, 27, 38, 0.85);
          color: #ffffff;
          transition-property: background-color;
          transition-duration: 0.5s;
          border-radius: 0px;
          margin: 0px;
          padding: 0px 0;
          min-height: 20px;
      }

      window#waybar.hidden {
        opacity: 0.2;
      }

      #workspaces button {
          padding: 3px 5px;
          margin: 3px 5px;
          border-radius: 6px;
          color: #d8dee9;
          background-color: transparent;
          transition: all 0.3s ease-in-out;
          font-size: 13px;
      }

      #workspaces button.active {
          color: #d8dee9;
          background: rgba(2, 89, 57, 0.6);
      }

      #workspaces button:hover {
          background: rgba(51, 51, 51, 0.6);
      }

      #workspaces button.urgent {
          background-color: #eb4d4b;
      }

      #workspaces {
          background-color: transparent;
          border-radius: 0px;
          padding: 3px 6px;
      }

      #window {
          background-color: transparent;
          font-size: 15px;
          font-weight: 800;
          color: #d8dee9;
          border-radius: 0px;
          padding: 3px 6px;
          margin: 2px;
          opacity: 1;
      }

      #clock,
      #battery,
      #cpu,
      #memory,
      #disk,
      #temperature,
      #backlight,
      #network,
      #pulseaudio,
      #wireplumber,
      #custom-media,
      #mode,
      #idle_inhibitor,
      #mpd,
      #bluetooth,
      #custom-hyprPicker,
      #custom-power-menu,
      #custom-spotify,
      #custom-launcher,
      #custom-power,
      #custom-pacman,
      #custom-screenshot_t,
      #custom-storage,
      #tray {
          background-color: transparent;
          border-radius: 0px;
          padding: 3px 6px;
          margin: 2px;
      }


      #cpu {
          color: #fb958b;
          background-color: #111827;
          padding: 4px;
      }

      #memory {
          color: #ebcb8b;
          background-color: #111827;
          padding: 4px;
      }

      #custom-power {
          background-color: transparent;
          color: #00aeff;
      }


      #custom-weather.severe {
          color: #eb937d;
      }

      #custom-weather.sunnyDay {
          color: #c2ca76;
      }

      #custom-weather.clearNight {
          color: #cad3f5;
      }

      #custom-weather.cloudyFoggyDay,
      #custom-weather.cloudyFoggyNight {
          color: #c2ddda;
      }

      #custom-weather.rainyDay,
      #custom-weather.rainyNight {
          color: #5aaca5;
      }

      #custom-weather.showyIcyDay,
      #custom-weather.snowyIcyNight {
          color: #d6e7e5;
      }

      #custom-weather.default {
          color: #dbd9d8;
      }

      .modules-left > widget:first-child > #workspaces {
          margin-left: 0;
      }

      .modules-right > widget:last-child > #workspaces {
          margin-right: 0;
      }

      #pulseaudio {
          color: #7d9bba;
      }

      #backlight {
          color: #8fbcbb;
      }

      #clock {
          color: #c8d2e0;
      }

      #battery {
          color: #c0caf5;
      }

      #battery.charging,
      #battery.full,
      #battery.plugged {
          color: #26a65b;
      }

      @keyframes blink {
          to {
              background-color: rgba(30, 34, 42, 0.5);
              color: #abb2bf;
          }
      }

      #battery.critical:not(.charging) {
          color: #f53c3c;
          animation-name: blink;
          animation-duration: 0.5s;
          animation-timing-function: linear;
          animation-iteration-count: infinite;
          animation-direction: alternate;
      }

      label:focus {
          background-color: #000000;
      }

      #disk {
          background-color: #964b00;
      }

      #bluetooth {
          color: #707d9d;
      }

      #bluetooth.disconnected {
          color: #f53c3c;
      }

      #network {
          color: #b48ead;
      }

      #network.disconnected {
          color: #f53c3c;
      }

      #custom-media {
          background-color: #66cc99;
          color: #2a5c45;
          min-width: 100px;
      }

      #custom-media.custom-spotify {
          background-color: #66cc99;
      }

      #custom-media.custom-vlc {
          background-color: #ffa000;
      }

      #temperature {
          background-color: #f0932b;
      }

      #temperature.critical {
          background-color: #eb4d4b;
      }

      #tray > .passive {
          -gtk-icon-effect: dim;
      }

      #tray > .needs-attention {
          -gtk-icon-effect: highlight;
          background-color: #eb4d4b;
      }

      #idle_inhibitor {
          background-color: #2d3436;
      }

      #idle_inhibitor.activated {
          background-color: #ecf0f1;
          color: #2d3436;
      }

      #language {
          background: #00b093;
          color: #740864;
          padding: 0 0px;
          margin: 0 5px;
          min-width: 16px;
      }

      #keyboard-state {
          background: #97e1ad;
          color: #000000;
          padding: 0 0px;
          margin: 0 5px;
          min-width: 16px;
      }

      #keyboard-state > label {
          padding: 0 0px;
      }

      #keyboard-state > label.locked {
          background: rgba(0, 0, 0, 0.2);
      }
    '';
  };
}
