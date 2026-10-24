{ palette }:
''
  from kitty.tab_bar import (
      apply_title_template,
      as_rgb,
      draw_attributed_string,
      sgr_sanitizer_pat,
      truncate_line,
      wcswidth,
      wrap_title,
  )

  BLUE = "${palette.blue}"


  def draw_tab(draw_data, screen, tab, before, max_tab_length, index, is_last, extra_data):
      # Kitty's built-in tab styles cannot underline the selected tab. Keep its
      # normal title rendering and apply an underline SGR only to the active tab.
      if draw_data.leading_spaces:
          screen.draw(" " * draw_data.leading_spaces)

      screen.cursor.fg = as_rgb(draw_data.tab_fg(tab))
      screen.cursor.bg = as_rgb(draw_data.tab_bg(tab))
      screen.cursor.bold = tab.is_active
      # Keep the two padding cells inside Kitty's allocated tab width. For very
      # narrow tabs, render a single ellipsis instead of letting padding overflow.
      if max_tab_length < 3:
          if max_tab_length > 0:
              screen.draw("…")
              if max_tab_length > 1:
                  screen.draw(" ")
      else:
          screen.draw(" ")
          if tab.is_active:
              red, green, blue = (int(BLUE[i:i + 2], 16) for i in (1, 3, 5))
              screen.apply_sgr(f"4:1;58:2::{red}:{green}:{blue}")

          title_width = max_tab_length - 2
          # A long title can wrap the Screen cursor before Kitty's native
          # post-draw ellipsis check runs. Clip to both the tab allocation and
          # remaining screen cells first, then retain the native cursor check as
          # a guard for unusual formatted titles.
          title_width = min(
              title_width,
              screen.columns - screen.cursor.x - 1 - (0 if is_last else 1),
          )
          title = apply_title_template(draw_data, tab, index, title_width)
          if draw_data.max_tab_title_lines > 1 and draw_data.wrap_width:
              title = wrap_title(title, draw_data.wrap_width)
          if "\n" in title:
              lines = title.split("\n")
              limit = max(1, draw_data.max_tab_title_lines)
              if len(lines) > limit:
                  del lines[limit:]
                  lines[-1] = truncate_line(lines[-1], draw_data.wrap_width or title_width)
              title = "\n".join(lines)
          title_cells = sum(
              max(0, wcswidth(part))
              for part in sgr_sanitizer_pat(for_splitting=True).split(title)
              if not part.startswith("\x1b")
          )
          if title_width > 0 and title_cells > title_width:
              title = truncate_line(title, title_width)
          elif title_width <= 0:
              title = ""
          draw_attributed_string(title, screen)

          if tab.is_active:
              screen.apply_sgr("24;59")
          # Match Kitty's native draw_tab_with_separator ellipsis handling, with
          # one extra cell reserved for each of our left and right title pads.
          extra = screen.cursor.x - before - (max_tab_length - 1)
          if extra > 0:
              screen.cursor.x -= extra + 1
              screen.draw("…")
          screen.draw(" ")

      screen.cursor.bold = False
      screen.cursor.bg = 0
      if not is_last:
          screen.cursor.fg = as_rgb(draw_data.inactive_fg)
          screen.draw(draw_data.sep)
      screen.cursor.bg = 0
      return screen.cursor.x
''
