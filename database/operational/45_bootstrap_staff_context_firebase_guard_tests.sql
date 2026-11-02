-- Regression coverage for the Firebase-only staff bootstrap guard.
-- Each DO statement runs in its own transaction, so LOCAL session context
-- is discarded automatically when the assertion block finishes. No user rows
-- or persistent session context are changed.
DO $test$
DECLARE
    expected_user TEXT := 'bootstrap-regression-user-sentinel';
    expected_company TEXT := 'bootstrap-regression-company-sentinel';
    expected_store TEXT := 'bootstrap-regression-store-sentinel';
BEGIN
    PERFORM set_config('app.current_user_id', expected_user, TRUE);
    PERFORM set_config('app.current_company_id', expected_company, TRUE);
    PERFORM set_config('app.current_store_id', expected_store, TRUE);

    IF mottainai.fn_bootstrap_staff_context(NULL, 'FIREBASE_UID') IS DISTINCT FROM FALSE THEN
        RAISE EXCEPTION 'NULL identity must be rejected';
    END IF;
    IF mottainai.fn_bootstrap_staff_context('test-identity', NULL) IS DISTINCT FROM FALSE THEN
        RAISE EXCEPTION 'NULL lookup type must be rejected';
    END IF;
    IF mottainai.fn_bootstrap_staff_context('test-identity', '') IS DISTINCT FROM FALSE THEN
        RAISE EXCEPTION 'Empty lookup type must be rejected';
    END IF;
    IF mottainai.fn_bootstrap_staff_context('test-identity', 'CPF') IS DISTINCT FROM FALSE THEN
        RAISE EXCEPTION 'Unsupported lookup type must be rejected';
    END IF;
    IF mottainai.fn_bootstrap_staff_context(NULL, 'FIREBASE_UID') IS DISTINCT FROM FALSE THEN
        RAISE EXCEPTION 'NULL Firebase UID must be rejected';
    END IF;
    IF mottainai.fn_bootstrap_staff_context('', 'FIREBASE_UID') IS DISTINCT FROM FALSE THEN
        RAISE EXCEPTION 'Empty Firebase UID must be rejected';
    END IF;
    IF mottainai.fn_bootstrap_staff_context('   ', 'FIREBASE_UID') IS DISTINCT FROM FALSE THEN
        RAISE EXCEPTION 'Whitespace-only Firebase UID must be rejected';
    END IF;
    IF mottainai.fn_bootstrap_staff_context('__qa_unknown_firebase_uid__', 'FIREBASE_UID') IS DISTINCT FROM FALSE THEN
        RAISE EXCEPTION 'Unknown Firebase UID must be rejected';
    END IF;

    IF current_setting('app.current_user_id', TRUE) IS DISTINCT FROM expected_user
       OR current_setting('app.current_company_id', TRUE) IS DISTINCT FROM expected_company
       OR current_setting('app.current_store_id', TRUE) IS DISTINCT FROM expected_store THEN
        RAISE EXCEPTION 'Rejected bootstrap attempts must not alter the current security context';
    END IF;

    RAISE NOTICE 'PASS: null, empty, unsupported and unknown bootstrap inputs fail closed without changing context';
END;
$test$;
