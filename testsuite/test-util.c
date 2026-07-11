#include <glib.h>

#include "src/ptyxis-util.h"

static void
assert_window_title_path (const char *title,
                          const char *expected)
{
  g_autofree char *path = ptyxis_window_title_to_path (title);

  g_assert_cmpstr (path, ==, expected);
}

static void
test_window_title_to_path (void)
{
  assert_window_title_path ("ivan@MI:/home/ivan/github/ptyxis",
                            "MI: /home/ivan/github/ptyxis");
  assert_window_title_path ("MI: ~/github/ptyxis",
                            "MI: ~/github/ptyxis");
  assert_window_title_path ("ivan@mi.tailnet:/var/log",
                            "mi.tailnet: /var/log");
  assert_window_title_path ("  ivan@MI:  /tmp  ",
                            "MI: /tmp");

  assert_window_title_path ("ssh ivan@MI", NULL);
  assert_window_title_path ("ivan@MI:relative/path", NULL);
  assert_window_title_path ("local shell", NULL);
}

static void
test_palette_id_for_terminal (void)
{
  g_assert_cmpstr (ptyxis_palette_id_for_terminal (0), ==, "gnome");
  g_assert_cmpstr (ptyxis_palette_id_for_terminal (1), ==, "Ubuntu");
  g_assert_cmpstr (ptyxis_palette_id_for_terminal (7), ==, "Tokyo Night Day");
  g_assert_cmpstr (ptyxis_palette_id_for_terminal (8), ==, "gnome");
  g_assert_cmpstr (ptyxis_palette_id_for_terminal (G_MAXUINT), ==, "Tokyo Night Day");
}

int
main (int argc,
      char *argv[])
{
  g_test_init (&argc, &argv, NULL);
  g_test_add_func ("/Ptyxis/Util/palette-id-for-terminal", test_palette_id_for_terminal);
  g_test_add_func ("/Ptyxis/Util/window-title-to-path", test_window_title_to_path);
  return g_test_run ();
}
