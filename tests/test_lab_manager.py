"""
Unit tests for the lab_manager.py orchestrator script.

These tests use the standard 'unittest' framework and 'unittest.mock' to
simulate host interactions, file system state, and subprocess executions
without requiring root privileges or modifying the actual host state.
"""

import os
import sys
import unittest
from unittest.mock import patch, mock_open, MagicMock

# Add the parent directory to the Python path to import lab_manager
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
import lab_manager


class TestLabManagerPreflight(unittest.TestCase):
    """Test suite for the pre-flight check logic."""

    @patch('sys.exit')
    @patch('builtins.print')
    @patch('os.path.exists', return_value=False)
    def test_missing_env_file(self, mock_exists, mock_print, mock_exit):
        """Test that missing .env file triggers sys.exit(1)."""
        lab_manager.check_preflight()
        mock_exists.assert_called_once_with(".env")
        mock_print.assert_any_call("Error: .env file missing. Please run setup_host.sh or create .env")
        mock_exit.assert_called_once_with(1)

    @patch('sys.exit')
    @patch('builtins.print')
    @patch('os.path.exists', return_value=True)
    def test_low_max_map_count(self, mock_exists, mock_print, mock_exit):
        """Test that vm.max_map_count < 262144 triggers sys.exit(1)."""
        
        def mock_open_side_effect(file, mode='r', *args, **kwargs):
            if file == "/proc/sys/vm/max_map_count":
                return mock_open(read_data="65530\n").return_value
            elif file == "/proc/swaps":
                return mock_open(read_data="Filename\tType\tSize\tUsed\tPriority\n").return_value
            raise FileNotFoundError(f"No such file: {file}")

        with patch('builtins.open', side_effect=mock_open_side_effect):
            lab_manager.check_preflight()

        mock_print.assert_any_call("Error: vm.max_map_count is too low (65530). Must be at least 262144.")
        mock_exit.assert_called_once_with(1)

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
            lab_manager.check_preflight()

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
            lab_manager.check_preflight()

        mock_print.assert_any_call("Pre-flight checks passed.")
        mock_exit.assert_not_called()


class TestLabManagerDockerRules(unittest.TestCase):
    """Test suite for the Docker iptables configuration logic."""

    @patch('subprocess.run')
    @patch('builtins.print')
    def test_apply_docker_user_rules_idempotency(self, mock_print, mock_run):
        """Test that rules are not redundantly added if they already exist."""
        # Simulate that `iptables -C` succeeds (return code 0) for all checks.
        mock_run.return_value = MagicMock(returncode=0)

        lab_manager.apply_docker_user_rules()

        # The loop should execute, calling `iptables -C` multiple times.
        # But `iptables -t <table/chain>` (the actual addition) should never be called.
        addition_calls = [
            call_args for call_args in mock_run.call_args_list
            if not "-C" in call_args[0][0] and "-D" not in call_args[0][0]
        ]
        self.assertEqual(len(addition_calls), 0)


class TestLabManagerCompose(unittest.TestCase):
    """Test suite for Docker Compose wrapper commands."""

    @patch('subprocess.run')
    @patch('builtins.print')
    def test_run_compose_up(self, mock_print, mock_run):
        """Test the translation of 'up' into a detached compose execution."""
        lab_manager.run_compose("up")
        mock_run.assert_called_once_with(["docker", "compose", "up", "-d"], check=True)

    @patch('subprocess.run')
    @patch('builtins.print')
    def test_run_compose_with_profile(self, mock_print, mock_run):
        """Test that compose profiles are correctly passed."""
        lab_manager.run_compose("down", profile="core")
        mock_run.assert_called_once_with(["docker", "compose", "--profile", "core", "down"], check=True)


class TestLabManagerMain(unittest.TestCase):
    """Test suite for the main orchestrator entry point."""

    @patch('sys.argv', ['lab_manager.py', 'invalid_action'])
    @patch('sys.exit')
    @patch('builtins.print')
    def test_invalid_action(self, mock_print, mock_exit):
        """Test that an invalid action terminates the script."""
        lab_manager.main()
        mock_print.assert_called_with("Unknown action: invalid_action")
        mock_exit.assert_called_once_with(1)

    @patch('sys.argv', ['lab_manager.py', 'status'])
    @patch('subprocess.run')
    def test_status_action(self, mock_run):
        """Test the 'status' action."""
        lab_manager.main()
        mock_run.assert_called_once_with(["docker", "compose", "ps"])

    @patch('sys.argv', ['lab_manager.py', 'up'])
    @patch('lab_manager.check_preflight')
    @patch('lab_manager.run_compose')
    @patch('lab_manager.apply_docker_user_rules')
    @patch('time.sleep')
    @patch('subprocess.run')
    @patch('builtins.print')
    def test_up_action(self, mock_print, mock_run, mock_sleep, mock_apply, mock_compose, mock_preflight):
        """Test the comprehensive sequence of the 'up' action."""
        lab_manager.main()
        
        mock_preflight.assert_called_once()
        mock_compose.assert_called_once_with("up")
        mock_apply.assert_called_once()
        mock_sleep.assert_called_once_with(15)
        # Assert that the validation script is executed
        mock_run.assert_called_once_with(["bash", "-x", "./validation.sh"], check=True)

if __name__ == '__main__':
    unittest.main()
