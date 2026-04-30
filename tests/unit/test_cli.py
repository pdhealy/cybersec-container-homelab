"""
Unit tests for the cli.py orchestrator script.

These tests use the standard 'unittest' framework and 'unittest.mock' to
simulate host interactions, file system state, and subprocess executions
without requiring root privileges or modifying the actual host state.
"""

import os
import sys
import unittest
from unittest.mock import patch, mock_open, MagicMock

# Add the parent directory to the Python path to import lab_manager
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '../../src')))
from cyberlab import cli


class TestLabManagerPreflight(unittest.TestCase):
    """Test suite for the pre-flight check logic."""

    @patch('questionary.confirm')
    @patch('sys.exit')
    @patch('builtins.print')
    @patch('os.path.exists', return_value=False)
    def test_missing_env_file(self, mock_exists, mock_print, mock_exit, mock_confirm):
        """Test that missing configs/.env file triggers secure password generation."""
        mock_confirm.return_value.ask.return_value = True
        
        def mock_open_side_effect(file, mode='r', *args, **kwargs):
            if file == "configs/.env.example":
                return mock_open(read_data="PIHOLE_PASSWORD=cyberhomelab_pihole_secure\nWAZUH_ADMIN_PASSWORD=cyberhomelab_wazuh_secure\nATTACKER_PASSWORD=cyberhomelab_attacker_secure\nSPLUNK_PASSWORD=cyberhomelab_splunk_secure\n").return_value
            elif file == "configs/.env":
                return mock_open().return_value
            elif file == "/proc/sys/vm/max_map_count":
                return mock_open(read_data="262144\n").return_value
            elif file == "/proc/swaps":
                return mock_open(read_data="Filename\tType\tSize\tUsed\tPriority\n").return_value
            raise FileNotFoundError(f"No such file: {file}")

        with patch('builtins.open', side_effect=mock_open_side_effect):
            cli.check_preflight()

        mock_exists.assert_called_once_with("configs/.env")
        mock_print.assert_any_call("Warning: configs/.env file missing. Generating secure passwords...")
        mock_exit.assert_not_called()

    @patch('subprocess.run')
    @patch('sys.exit')
    @patch('builtins.print')
    @patch('os.path.exists', return_value=True)
    def test_low_max_map_count(self, mock_exists, mock_print, mock_exit, mock_run):
        """Test that vm.max_map_count < 262144 triggers automated host setup."""
        
        def mock_open_side_effect(file, mode='r', *args, **kwargs):
            if file == "/proc/sys/vm/max_map_count":
                return mock_open(read_data="65530\n").return_value
            elif file == "/proc/swaps":
                return mock_open(read_data="Filename\tType\tSize\tUsed\tPriority\n").return_value
            raise FileNotFoundError(f"No such file: {file}")

        with patch('builtins.open', side_effect=mock_open_side_effect):
            cli.check_preflight()

        mock_print.assert_any_call("Warning: vm.max_map_count is too low (65530). Automating host setup...")
        mock_run.assert_called_once_with(["sudo", "bash", "scripts/setup_host.sh"], check=True)
        mock_exit.assert_not_called()

    @patch('sys.exit')
    @patch('builtins.print')
    @patch('os.path.exists', return_value=True)
    def test_swap_enabled(self, mock_exists, mock_print, mock_exit):
        """Test that active swap partitions trigger sys.exit(1)."""
        
        def mock_open_side_effect(file, mode='r', *args, **kwargs):
            if file == "/proc/sys/vm/max_map_count":
                return mock_open(read_data="262144\n").return_value
            elif file == "/proc/swaps":
                return mock_open(read_data="Filename\tType\tSize\tUsed\tPriority\n/dev/sda2\tpartition\t1024\t0\t-2\n").return_value
            raise FileNotFoundError(f"No such file: {file}")

        with patch('builtins.open', side_effect=mock_open_side_effect):
            cli.check_preflight()

        mock_print.assert_any_call("Error: Swap is enabled. Disable it with 'sudo swapoff -a' for optimal performance.")
        mock_exit.assert_called_once_with(1)

    @patch('sys.exit')
    @patch('builtins.print')
    @patch('os.path.exists', return_value=True)
    def test_preflight_success(self, mock_exists, mock_print, mock_exit):
        """Test that pre-flight checks pass when all conditions are met."""
        
        def mock_open_side_effect(file, mode='r', *args, **kwargs):
            if file == "/proc/sys/vm/max_map_count":
                return mock_open(read_data="262144\n").return_value
            elif file == "/proc/swaps":
                return mock_open(read_data="Filename\tType\tSize\tUsed\tPriority\n").return_value
            raise FileNotFoundError(f"No such file: {file}")

        with patch('builtins.open', side_effect=mock_open_side_effect):
            cli.check_preflight()

        mock_print.assert_any_call("Pre-flight checks passed.")
        mock_exit.assert_not_called()


class TestLabManagerCompose(unittest.TestCase):
    """Test suite for Docker Compose wrapper commands."""

    @patch('subprocess.run')
    @patch('builtins.print')
    def test_run_compose_up(self, mock_print, mock_run):
        """Test the translation of 'up' into a detached compose execution."""
        cli.run_compose("up")
        mock_run.assert_called_once_with(["docker", "compose", "--env-file", "configs/.env", "up", "-d"], check=True)

    @patch('subprocess.run')
    @patch('builtins.print')
    def test_run_compose_with_profile(self, mock_print, mock_run):
        """Test that compose profiles are correctly passed."""
        cli.run_compose("down", profiles=["core"])
        mock_run.assert_called_once_with(["docker", "compose", "--env-file", "configs/.env", "--profile", "*", "down"], check=True)


class TestLabManagerMain(unittest.TestCase):
    """Test suite for the main orchestrator entry point."""

    @patch('sys.argv', ['cyberlab.py', 'invalid_action'])
    @patch('sys.exit', side_effect=SystemExit(2))
    @patch('sys.stderr.write')
    def test_invalid_action(self, mock_stderr, mock_exit):
        """Test that an invalid action terminates the script."""
        with self.assertRaises(SystemExit) as cm:
            cli.main()
        self.assertEqual(cm.exception.code, 2)
        mock_exit.assert_called_once_with(2)

    @patch('sys.argv', ['cyberlab.py', 'status'])
    @patch('subprocess.run')
    def test_status_action(self, mock_run):
        """Test the 'status' action."""
        cli.main()
        mock_run.assert_called_once_with(["docker", "compose", "--env-file", "configs/.env", "ps"])

    @patch('sys.argv', ['cyberlab.py', 'up'])
    @patch('cyberlab.cli.check_preflight')
    @patch('cyberlab.cli.run_compose')
    @patch('time.sleep')
    @patch('subprocess.run')
    @patch('builtins.print')
    @patch('cyberlab.cli.interactive_mode', return_value=['core'])
    @patch('cyberlab.cli.write_active_lab_env')
    def test_up_action(self, mock_write, mock_interactive, mock_print, mock_run, mock_sleep, mock_compose, mock_preflight):
        """Test the comprehensive sequence of the 'up' action."""
        cli.main()
        
        mock_preflight.assert_called_once()
        mock_compose.assert_called_once_with("up", ["core"])
        mock_sleep.assert_called_once_with(15)
        # Assert that the validation script is executed
        mock_run.assert_any_call(["bash", "./scripts/validation.sh"], check=True)

if __name__ == '__main__':
    unittest.main()
