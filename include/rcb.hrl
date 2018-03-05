-define(APP, rcb).
-define(METRICS_DEFAULT, false).
-define(DEFAULT_LATENCY, 0). %% in milliseconds

-define(PEER_SERVICE, partisan_peer_service).
-define(PEER_SERVICE_MANAGER, partisan_default_peer_service_manager).
-define(HANDLER, rcb_handler).
-define(RESENDER, rcb_resender).
-define(FIRST_RCBCAST_TAG, first).
-define(RESEND_RCBCAST_TAG, first).
-define(WAIT_TIME_BEFORE_CHECK_RESEND, 5000).
-define(WAIT_TIME_BEFORE_RESEND, 10000).

-type actor() :: term().
-type message() :: term().
-type timestamp() :: vclock:vclock().
-type vclock() :: vclock:vclock().

%% logging
-ifdef(debug).
-define(LOG(M), lager:info(M)).
-define(LOG(M, A), lager:info(M, A)).
-else.
-define(LOG(_M), ok).
-define(LOG(_M, _A), ok).
-endif.
