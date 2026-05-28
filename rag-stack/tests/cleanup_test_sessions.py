from e2e_session_state import cleanup_test_sessions


if __name__ == "__main__":
    print("[CLEANUP] Removing stale test sessions before E2E run...")
    cleanup_test_sessions()
    print("[CLEANUP] Session cleanup complete.")
