"""Run the package suite without tests that need a user-owned filesystem root."""

import sys
import unittest


EXCLUDED = {
    "tests.test_hardening.ImportedFolders.test_choosing_the_folder_here_gives_its_podcast_its_files_back",
    "tests.test_hardening.LocalFolders.test_files_stay_unless_the_user_confirms_and_then_go_to_the_trash",
    "tests.test_hardening.SharedFolders.test_files_of_an_added_folder_that_others_can_change_stay",
}


def without_excluded(suite):
    kept = unittest.TestSuite()
    for item in suite:
        if isinstance(item, unittest.TestSuite):
            kept.addTests(without_excluded(item))
        elif item.id() not in EXCLUDED:
            kept.addTest(item)
        else:
            print(f"excluded in the Nix sandbox: {item.id()} (/ is owned by nobody)", flush=True)
    return kept


suite = unittest.defaultTestLoader.discover("tests", pattern="test*.py", top_level_dir=".")
sys.exit(not unittest.TextTestRunner(verbosity=2).run(without_excluded(suite)).wasSuccessful())
