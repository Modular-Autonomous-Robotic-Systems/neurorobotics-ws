# Project AirSim `/clock` Publication Bug

This document tracks a live investigation into why `projectairsim_ros2_cpp_node` never publishes on `/clock`, despite advertising the topic and despite every other bridged topic working normally. It is written incrementally as the investigation proceeds, and later sessions should append new sub-sections to Investigations, and new evidence to Root Cause and Solution, rather than rewriting what is already established here.

## 1. Introduction

The Basalt SLAM stack fuses two ROS 2 streams from the SITL setup described in `djinn start sitl2`, namely `/ap/imu/experimental/data` from ArduPilot's AP_DDS bridge and `/airsim_node/Copter/front_center_Scene/image` from the Project AirSim ROS 2 bridge. `context/gt_slam_alignment.md`'s sibling document, [`ap_dds_imu_stream.md`](../ros_ws/src/slam/ext/basalt/context/ap_dds_imu_stream.md), establishes that these two streams are stamped from entirely different clocks. The image stamp comes from Project AirSim's own simulation clock, which starts at zero, while the inertial stamp comes from ArduPilot's RTC, which falls back to a UTC-derived wall clock epoch whenever ArduPilot has not received any messages on the ROS `/clock` topic. A capture taken directly from the running stack during this investigation confirms the mismatch is still live.

```
/ap/imu/experimental/data   header.stamp:  sec: 1787205506, nanosec: 993770000
/airsim_node/.../image      header.stamp:  sec: 1499,       nanosec: 130000000
```

The inertial stamp is a ten-digit UTC epoch and the image stamp is a four-digit simulation-time figure, so the two streams differ by roughly 1.787 billion seconds. `ap_dds_imu_stream.md` §"The epoch mismatch between the inertial and visual streams" already establishes why this is fatal to Basalt, namely that its preintegration window between a frame and its surrounding inertial samples places every image outside the inertial window entirely once the two streams disagree by more than a few tens of milliseconds, so the estimator receives no usable visual-inertial constraint at all. That same section identifies the remedy as ensuring ArduPilot takes the `/clock` branch of `AP_DDS_Client::update_topic`, which requires `has_received_clock` to be true, which in turn requires ArduPilot's DDS client to have actually received at least one message on `/clock`.

This investigation establishes that it never does, because `projectairsim_ros2_cpp_node`, the sole publisher of `/clock` in this stack, never emits a single message on that topic. `ros2 topic info /clock -v` shows the publisher endpoint correctly advertised with a QoS profile compatible with both of `/clock`'s subscribers (`ap` and `managed_logger_node`), and `ros2 node info /projectairsim_ros2_cpp_node` lists `/clock` among its publishers, so the topic exists in the ROS graph in every way that static introspection can check. When `ros2 topic echo /clock` and `ros2 topic hz /clock` are run live against the running stack repeatedly across this investigation, the commands consistently time out with zero messages received. The remainder of this document works through the request-response transport that `/clock`'s publication depends on, in order to explain that silence.

## 2. Software Architecture

`/clock`'s value comes from a single call chain, `PublishClock()` inside `projectairsim_ros2_cpp_node.cpp` calling `RequestSimTime()`, which asks the Project AirSim server for its current simulation time over the same request-response transport that every other synchronous service in this bridge uses. Understanding why that one call never returns requires understanding the full path a request takes from the ROS 2 node, through the C++ client library, over the network, into the simulation core's service dispatcher, and back. §2.1 and §2.2 below cover the client side and the server side of that path in full, both illustrated with the exact call that stalls, `GetSimTime`. §2.3 then steps back from the stall itself to record, as background for possible future work, why simulation time is exposed this way at all rather than as a topic like every other sensor stream.

### 2.1 Project AirSim Client Request-Response Architecture

The client library lives at `sitl_ws/src/ue5/ProjectAirSim/client/cpp/ProjectAirsimClientLib/src/Client.cpp`, and its `Client::Impl` class is the object the ROS 2 bridge holds as `client_`. `Client::Impl::Connect()` (`Client.cpp:448-512`) opens a plain NNG REQ0 socket for the request-response channel, `nng_socket_services_`, with three socket options set before dialling the server.

```cpp
nngi::nng_socket_set_ms(nng_socket_services_, NNG_OPT_RECVTIMEO, kSecResponseReceiveTimeout);  // 300000 ms
nngi::nng_socket_set_ms(nng_socket_services_, NNG_OPT_SENDTIMEO, kSecRequestSendTimeout);       // 1000 ms
nngi::nng_socket_set_ms(nng_socket_services_, NNG_OPT_REQ_RESENDTIME, kSecRequestRetryTime);    // -1, disabled
```

`Connect()` then starts two long-lived background threads that persist for the lifetime of the connection, `RequestSendingThreadProc()` and `ResponseReceivingThreadProc()`. Every synchronous call an application makes, including `RequestSimTime()`'s call to `client_->Request("/Sim/StonePineForestArduCopter/GetSimTime", {}, &response)`, passes through these two threads rather than sending and receiving on the calling thread directly.

The flow chart below traces one `GetSimTime` request end to end through the client, naming the four participants involved, the calling application thread, the two background threads, and the NNG socket itself.

```
Application thread                     Client::Impl                            RequestSendingThreadProc                 ResponseReceivingThreadProc                     NNG socket / server
(ROS 2 executor, inside                                                        (background thread, loops forever)       (background thread, loops forever)
 PublishClock -> RequestSimTime)

|
| client_->Request(method, params, &response)
v
                                        Client::Impl::Request()
                                            |
                                            | RequestAsync(method, params)
                                            v
                                        new TAsyncResultProvider(parp)
                                        lock(mutex_message_queues_)
                                        list_pending_request_entry_.push_back({method, params, parp})
                                        cv_pending_request_.notify_all()
                                        unlock
                                            |
                                            | returns TAsyncResult immediately, non-blocking so far
                                            v
                                        ar.Wait()
                                            blocks on cv_done_, NO TIMEOUT, until SetDone() is called on parp.
                                            Unblocked only when the ResponseReceivingThreadProc column, far to
                                            the right below, calls SetDoneResult()/SetDone() on this same parp.

                                                                                wakes on cv_pending_request_
                                                                                dequeues the entry
                                                                                calls SendRequest(method, params, parp)
                                                                                    |
                                                                                    | lock(mutex_message_send_)
                                                                                    | build RequestMessage(request_id_next_, method, params)
                                                                                    | nng_send(nng_socket_services_, ...)
                                                                                    |     -----------------------------------------------------------------------------> travels to server
                                                                                    | on success:
                                                                                    |     list_pending_response_entry_.push_back({id, parp})
                                                                                    |     cv_pending_response_.notify_all()
                                                                                    |     ++request_id_next_
                                                                                    | unlock

                                                                                                                            wakes on cv_pending_response_
                                                                                                                            dequeues the entry (FIFO)
                                                                                                                            for (;;) {
                                                                                                                                nng_recv(nng_socket_services_,
                                                                                                                                         ..., 300000 ms timeout)
                                                                                                                                    <----------------------------------- server replies (normal case)
                                                                                                                                if OK:
                                                                                                                                    parp->SetDoneResult(message)
                                                                                                                                        --> unblocks Application
                                                                                                                                            thread's ar.Wait()
                                                                                                                                            above, with the
                                                                                                                                            response
                                                                                                                                    break
                                                                                                                                else if ETIMEDOUT and still running:
                                                                                                                                    continue
                                                                                                                                        -- loops back to
                                                                                                                                           nng_recv() again,
                                                                                                                                           same pending entry,
                                                                                                                                           no SetDone(), ever
                                                                                                                                else if ECANCELED / ECLOSED / other error:
                                                                                                                                    parp->SetDone(status)
                                                                                                                                        --> unblocks Application
                                                                                                                                            thread's ar.Wait()
                                                                                                                                            above, with an error
                                                                                                                                    break
                                                                                                                            }
```

The blocking wrapper the ROS 2 node actually calls, `Client::Impl::Request()` (`Client.cpp:581-595`), is nothing more than `RequestAsync(...).Wait()` with a `try`/`catch` around it. `RequestAsync()` (`:597-621`) does no networking itself, it only appends a `PendingRequestEntry` to `list_pending_request_entry_` under `mutex_message_queues_` and returns immediately, so the calling thread's actual wait happens entirely inside `Wait()`. `Wait()` is defined once, in `AsyncResultInternal.h:54-60`, and is shared by every asynchronous operation in the library.

```cpp
virtual Status Wait(void) override {
  std::unique_lock ul(mutex_);
  while (!fis_done_) cv_done_.wait(ul);
  return (status_);
}
```

There is no timeout parameter anywhere in this function or in any overload of it. The only way this wait ever returns is for some other thread to call `SetDone()` on this exact `TAsyncResultProvider` object, which sets `fis_done_` and notifies `cv_done_`. This is the first structural reason a stuck request hangs forever rather than merely for a long time, the primitive the whole synchronous API is built on has no bound of its own.

`RequestSendingThreadProc()` (`:716-776`) is the thread that turns a queued `PendingRequestEntry` into an actual network send. It sleeps on `cv_pending_request_` in half-second slices when the queue is empty, and when a request is available it calls `SendRequest()` (`:870-896`), which serialises the request with `msgpack`, calls `nng_send()` on `nng_socket_services_`, and, on a successful send, moves the same `TAsyncResultProvider` pointer into a new `PendingResponseEntry` appended to `list_pending_response_entry_`. This is the handoff between the sending side and the receiving side, the two lists are deliberately separate, guarded by two separate mutexes, `mutex_message_queues_` for the outgoing queue and `mutex_message_send_` for the awaiting-reply queue, and the sending thread never itself waits for a reply, it only sends and then immediately loops back to see if another request is queued.

`ResponseReceivingThreadProc()` (`:778-865`) is the thread that turns a network reply into a completed `TAsyncResult`. It sleeps on `cv_pending_response_` the same way, and once it has dequeued a `PendingResponseEntry`, it enters the inner `for (;;)` loop shown in the flow chart above, calling `nng_recv()` on the same `nng_socket_services_` socket. Three outcomes are handled explicitly, a genuine error completes the request with a failure status, a successful receive completes the request with the response message, and a socket-level timeout, which the code can distinguish because `NNG_OPT_RECVTIMEO` was set to 300000 ms in `Connect()`, is treated as a reason to `continue` the loop and call `nng_recv()` again rather than as a reason to give up.

Because response processing thread is a single, shared loop over the whole list of pending responses, and because it retries the exact same pending entry indefinitely on a timeout, a single unanswered request stalls not only its own caller but every request queued behind it in `list_pending_response_entry_`, since the thread never advances past the front of that list until the current entry resolves one way or another.

Two further design choices amplify this failure mode. First, `kSecRequestRetryTime` (`NNG_OPT_REQ_RESENDTIME`) is set to `-1`, which is NNG's own built-in mechanism for automatically re-sending a request if no reply arrives within a given time, and it is explicitly disabled here. So even if the original request message was lost in transit, silently, nothing at the transport layer will ever re-send it, the client is entirely dependent on getting exactly one reply for exactly one send.

Second, matching a reply to the correct waiting caller is purely positional, `list_pending_response_entry_` is a FIFO list and `ResponseReceivingThreadProc()` always completes whichever entry is currently at the front, there is no verification that the `request_id` embedded in the received message actually matches the `request_id` recorded in the `PendingResponseEntry` it is about to complete. Under the plain REQ0 socket used here, which supports only one request in flight at a time from the socket's own perspective, this ordering assumption is safe as long as the sending and receiving threads never allow two sends to overlap without an intervening receive, but it does mean the receiving thread has no independent way to detect a mismatch if that assumption is ever violated.

It may be tempting to assume that because there is only one response-receiving thread, and all requests funnel through it, a stuck request would also starve every subscribed topic behind it, the same way a stuck request starves every other pending request. This is not what happens, because requests and topics are two entirely separate channels at the transport level, not two consumers of the same queue.

`Client::Impl` opens two independent NNG sockets in `Connect()`, `nng_socket_services_`, a `req0` socket opened with `nng_req0_open()` (`Client.cpp:453`) and used exclusively by `RequestSendingThreadProc()`/`ResponseReceivingThreadProc()` for the request/response protocol, and `nng_socket_topics_`, a `pair0` socket opened with `nng_pair0_open()` (`:476`) and used exclusively for the topic data stream. Topic reception is started by `topics_.StartReceiving()` (`:489`), which is a call into the separate `internal::Topics` object, and `Topics::StartReceiving()` (`Topics.cpp:173-180`) spawns its own dedicated thread, `TopicReceiveThreadProc()`, that blocks on `nng_recv()` against `nng_socket_topics_`, not `nng_socket_services_`. So there are, in total, three background threads running inside a connected `Client`, not two, `RequestSendingThreadProc` and `ResponseReceivingThreadProc` sharing the services socket, plus `TopicReceiveThreadProc` owning the topics socket outright.

A `GetSimTime` request stuck inside `ResponseReceivingThreadProc()`'s retry loop only ever blocks that one thread and whatever is queued behind it in `list_pending_response_entry_`, it has no code path that touches `nng_socket_topics_`, `topics_`, or `TopicReceiveThreadProc()`'s thread, so images and IMU samples, which arrive over the topics socket, keep flowing without interruption. This is precisely what the logs already show, `/airsim_node/.../image` keeps publishing throughout every captured stall, only `/clock`, which is fed exclusively by the stuck `GetSimTime` request/response exchange, stops.

A stuck `GetSimTime` reply does not only threaten future `GetSimTime` calls. `list_pending_response_entry_` is a single, shared FIFO, so a stuck entry at its head blocks the reply to whatever request is queued behind it, regardless of which service that request targets. The flow chart below traces every automatic request-response call `projectairsim_ros2_cpp_node` makes, from construction up to the moment an external client could first invoke `takeoff`, to establish whether `GetSimTime`'s own first request could itself be queued behind some earlier, already-stuck call.

```
Constructor start
  |
  | client_->Connect()
  |     -- socket setup only, no req0 traffic
  v
  scene_config_ parameter set?
    |
    |-- yes --> world_->Initialize()  ->  LoadScene()  ->  pclient_->RequestLoadScene()
    |             |
    |             | client_->Request("/Sim/LoadScene", ...)
    |             |     <-- the ONE req0 request made at startup
    |             v
    |           status != OK?  --yes--> throw, node never starts, nothing is ever logged
    |             |
    |             | no
    |             v
    |           scene_loaded_ = true
    |               (request already resolved, queue now empty)
    |
    |-- no ---> AdoptLoadedSceneIfAvailable()  ->  world_->Initialize(client_)  ->  pclient_->GetTopicInfo()
                  |
                  | topics_.GetAll()
                  |     -- LOCAL ONLY, reads the topics-socket cache, no req0 traffic at all
                  v
                scene_loaded_ = true
                    (req0 queue never touched)
  |
  v
CreateServices()  /  CreateActionServer()
  |     -- registers ~25 callbacks, no calls made
  v
DiscoverAndSubscribeIfReady()  ->  DiscoverAndSubscribe()
  |
  | client_->GetTopicInfo()
  |     -- LOCAL ONLY
  | client_->Subscribe() x N topics
  |     -- LOCAL ONLY (topics_.Subscribe), no req0
  v
StartClockTimerIfReady()
  |     -- creates the wall timer only, no call yet
  v
Constructor returns, rclcpp::spin() begins (SingleThreadedExecutor)
  |
  |     [ req0 response queue is EMPTY here in every startup path: either the one LoadScene
  |       request already resolved, or the empty-scene_config_ path never touched req0 at all ]
  |
  | ~5 ms later, clock_timer_ fires for the first time
  v
PublishClock()  ->  RequestSimTime()  ->  client_->Request("GetSimTime", ...)
      <-- first entry queued
```

The chart establishes that under normal startup there is no internally-issued request left ahead of `GetSimTime` in the queue. The only automatic req0 traffic the node produces is the one-time `LoadScene` request, and that request has necessarily already resolved by the time the constructor returns, since the constructor throws on failure and the node would never reach `rclcpp::spin()` at all.

That leaves only an externally-triggered call as a candidate predecessor, some other ROS 2 client invoking `takeoff`, `arm`, `spawn_object`, or a similar wrapped service, just before the clock timer's first tick, whose own reply was lost, with `GetSimTime` left queued behind it.

`projectairsim_ros2_cpp_node` runs on a plain `rclcpp::spin()`, a default `SingleThreadedExecutor`. Only one ROS 2 callback executes at a time. If an earlier service callback were already stuck inside its own `client_->Request(...).Wait()`, the executor's single thread would be permanently occupied by that callback, and `PublishClock()` could never be dispatched at all.

Every captured session shows the opposite. `"PublishClock: tick received"` fires, `"RequestSimTime: Entered after mutex"` logs, and the hang is observably inside `GetSimTime`'s own call, with no earlier `"<service>: request received"` log lacking a matching `"request completed"`. That pattern is only possible if `PublishClock` itself was the callback that captured the executor's one thread and stalled there, not a victim queued behind an earlier stuck call.

So the `SingleThreadedExecutor`'s own serialisation rules out "stuck behind an earlier request from this node" as an explanation, it structurally cannot happen while this node runs single-threaded, since two callbacks can never overlap in the first place. This protection is coincidental rather than deliberate, it falls out of single-threading, not out of any synchronisation inside the client library itself.

A `MultiThreadedExecutor` would remove that coincidental protection. Two callbacks could then call `client_->Request()` concurrently, and the exact FIFO-starvation scenario considered above would become live, a second, unrelated request genuinely queued ahead of `GetSimTime`'s. This would be compounded by the pointer-and-FIFO-position correlation mechanism described above, which has no `request_id` cross-check to catch a reply being matched to the wrong caller if two sends were ever in flight at once.

Using a `MultiThreadedExecutor` here would remove the whole-node freeze this document traces, one stuck callback no longer blocks every other callback, but it would introduce cross-request FIFO starvation and reply misattribution as new risks, unless the client library's request-response matching is also changed to correlate by `request_id` rather than by queue position. A timeout fix, such as §4.4's, is required either way and is not sufficient on its own to make a `MultiThreadedExecutor` safe here.

The mechanism for response handling and streaming data correctly to the client invoking application is not a lookup by ID at all. Instead, it is a pointer carried unchanged through both queues. `RequestAsync()` (`:597-621`) allocates one `internal::TAsyncResultProvider<Message>* parp` per call and stores that exact pointer inside the `PendingRequestEntry` it pushes onto `list_pending_request_entry_`. When `RequestSendingThreadProc()` (`:716-776`) dequeues that entry, it lifts the same pointer out (`:734-737`, "Shortcut: take ownership of the reference count") and hands it straight into `SendRequest()` (`:870-896`), which, immediately after a successful `nng_send()`, constructs a `PendingResponseEntry` from that same pointer plus the outgoing `request_id_next_` and appends it to `list_pending_response_entry_` (`:888-890`). The pointer, in other words, is the correlation token, it is never looked up by ID at any point, it is simply carried forward, unchanged, from the moment the caller's `Request()`/`RequestAsync()` call creates it to the moment `ResponseReceivingThreadProc()` calls `pasyncresultprovider_message->SetDoneResult(...)` or `SetDone(...)` on it.

This is also why the earlier statement that matching is "purely positional" is the accurate framing rather than "by callback", the `FnResponseCallback` passed into `RequestAsync()` is optional and, when present, is invoked from inside `TAsyncResultProvider` as a side effect of `SetDone`/`SetDoneResult` completing, it plays no role in deciding which reply belongs to which request, that decision was already made, implicitly, by FIFO queue order at enqueue time.

The `request_id` field is populated on both ends (`RequestMessage` on send, presumably echoed in the server's `ResponseMessage`, `ResponseReceivingThreadProc()` even captures it into a local `request_id` variable at `:781`) but that captured value is used only for the diagnostic log line on error (`:838-840`), it is never compared against anything in the received message. So the correctness of the whole scheme rests entirely on the invariant already noted above, that the plain REQ0 socket carries at most one outstanding request at a time and that the two FIFO lists are only ever appended to and popped from their respective ends, never reordered. If that invariant were ever violated, for instance by two sends racing ahead of their receives, the pointer-matching scheme would silently deliver the wrong reply to the wrong caller with no detection, since nothing here ever inspects `request_id` to catch the mismatch.

It must be noted that `run_request_threads_` is a plain `bool` member (`Client.cpp:307-308`), read continuously by both `RequestSendingThreadProc()` and `ResponseReceivingThreadProc()` in their `while (run_request_threads_)` loop conditions, and written exactly twice, to `true` in `Connect()` (`:495`) and to `false` in `DisconnectCore()` (`:549`). The observation that writes are rare and reads are frequent is correct, and in practice this pattern rarely misbehaves on the common desktop and server platforms this code targets, because a `bool` write is atomic at the hardware level on those platforms and the two background threads only need to observe the transition from `true` to `false` within roughly half a second, bounded by the `wait_until` timeouts already in their loops, in order to exit cleanly.

That said, the absence of `std::atomic<bool>` or a memory fence here is still formally a data race under the C++ memory model, since `run_request_threads_` is written by the thread that calls `Disconnect()` while being read without synchronisation by both background threads, and the language standard does not guarantee the write becomes visible to the reading threads in bounded time, or at all, in the absence of a happens-before relationship. The consequence of that race manifesting would be a thread that fails to notice shutdown promptly and blocks the destructor's `join()` calls in `DisconnectCore()` (`:550-557`) for longer than expected, not the silent, unbounded `/clock` stall this document is chasing, since neither background thread's ordinary operation depends on `run_request_threads_` changing except at shutdown.

The decision reached here is to leave it as a plain `bool` rather than convert it to `std::atomic<bool>`, because `run_request_threads_` is read on every single iteration of both threads' tight polling loops, `RequestSendingThreadProc()`'s outer `while` and its inner `while` guarding `cv_pending_request_.wait_until()`, and likewise for `ResponseReceivingThreadProc()`, and converting a variable read this frequently to an atomic, even with the relaxed memory ordering that would suffice here, introduces a real, if small, per-iteration cost, a cost paid on every poll for the entire lifetime of the connection in exchange for a correctness property that only matters once, at shutdown, and whose failure mode is a slower `join()` rather than data corruption or the defect under investigation. This is a case where the formally correct fix is not the practically justified one, given the frequency of the read against the rarity and low severity of the write.

It is worth revisiting only if `DisconnectCore()` is ever observed to hang or to take noticeably longer than the half-second polling interval would predict. The core simulation server, discussed next, has an analogous flag protecting a similar shutdown path, `ServiceManager::Impl::is_alive_`, and it is declared `std::atomic<bool>` (`service_manager.cpp:128`), which remains worth noting as the more conservative pattern even though the reasoning above is why this document does not recommend matching it here.

### 2.2 Core Simulation Request-Response Architecture

The server side lives in `core_sim/src/service_manager.cpp`. Every simulation object that exposes remote-callable methods, including `Scene`, registers them once, at construction, into a single shared table. For `GetSimTime`, that registration happens in `Scene::Impl::RegisterServiceMethods()` (`scene.cpp:827-836`).

```cpp
auto sim_get_time = ServiceMethod("GetSimTime", {""});
auto sim_get_time_handler = sim_get_time.CreateMethodHandler(&Scene::Impl::SimGetTime, *this);
RegisterServiceMethod(sim_get_time, sim_get_time_handler);
```

`RegisterServiceMethod()` (`scene.cpp:813-825`) prefixes the method name with the scene's own topic path, producing the full method name `/Sim/StonePineForestArduCopter/GetSimTime` that the client's log lines showed being requested, and calls `ServiceManager::Impl::RegisterMethod()` (`service_manager.cpp:256-263`), which simply inserts the name and handler into `methods_registry_`, a `std::map<std::string, MethodHandler>`.

The handler itself, `Scene::Impl::SimGetTime()` (`scene.cpp:665`), is a single line, `return sim_time_;`, so the server-side computation for this particular method can never itself be the source of a delay.

The interesting architecture is in how a request actually reaches that handler. `ServiceManager` does not run a simple accept-and-block loop, it uses NNG's asynchronous context API to service up to `kMaxConcurrentJobs`, 64, requests concurrently on a single `nng_rep0` socket (`service_manager.cpp:114,187`).

`Start()` (`:182-232`) opens the socket, creates 64 `Job` structures, each with its own `nng_ctx` sharing the one socket and its own `nng_aio` asynchronous I/O handle bound to a single callback, `JobRunner()`, then calls `JobRunner()` once per job to prime all 64 into their initial listening state. The flow chart below traces one `GetSimTime` request through this machinery.

```
Scene construction                         ServiceManager::Start()                    NNG async runtime                          RunJob() state machine                    Client
(once, at scene load)                      (once, at server start)                    (invoked by NNG's own worker                (invoked as the nng_aio callback          (sends request,
                                                                                        threads whenever a context's                for whichever job's I/O                   waits for reply)
                                                                                        I/O completes)                              just completed)

|
| RegisterServiceMethod("GetSimTime",
|                       &Scene::Impl::SimGetTime)
v
methods_registry_["/Sim/.../GetSimTime"]
    = handler
(plain std::map, no lock taken here
 or anywhere it is read)

                                            |
                                            | nng_rep0_open(&service_socket_)
                                            | for each of 64 jobs:
                                            |     nng_aio_alloc(&job.aio, JobRunner, &job)
                                            |     nng_ctx_open(&job.ctx, service_socket_)
                                            | nng_listen(service_socket_, "tcp://...")
                                            | for each of 64 jobs:
                                            |     JobRunner(&job)
                                            |         -- primes every job into kListening.
                                            |            This first call happens
                                            |            synchronously inside Start()
                                            |            itself, on Start()'s own thread,
                                            |            not on an NNG worker thread.
                                            v
                                                                                                                                    RunJob(): case kListening:
                                                                                                                                        ResetJob(job)
                                                                                                                                        job->state = kProcessing
                                                                                                                                        nng_ctx_recv(job->ctx, job->aio)
                                                                                                                                            <-- async, returns
                                                                                                                                                immediately, no
                                                                                                                                                thread blocks here
                                                                                                                                        |
                                                                                                                                        |  (idle, waiting)
                                                                                                                                        |
                                                                                                                                                                                   | nng_send(request)
                                                                                                                                                                                   v
                                                                                        a free job's context receives
                                                                                        the message, NNG's worker pool
                                                                                        invokes JobRunner(job) again
                                                                                            |
                                                                                            v
                                                                                                                                    RunJob(): case kProcessing:
                                                                                                                                        deserialize RequestMessage
                                                                                                                                        job->request_method =
                                                                                                                                            "/Sim/.../GetSimTime"
                                                                                                                                        RequestResponse(job)
                                                                                                                                            methods_registry_->find(method)
                                                                                                                                                <-- unsynchronized read
                                                                                                                                            ProcessRequest(...)
                                                                                                                                                validate params (none
                                                                                                                                                required) and authorization
                                                                                                                                                result = method_handler(args)
                                                                                                                                                    -- SimGetTime() -> sim_time_
                                                                                                                                                response = SerializeResponse(
                                                                                                                                                    ResponseSuccessMessage(...))
                                                                                                                                        job->state = kListening
                                                                                                                                        nng_aio_set_msg(job->aio, response)
                                                                                                                                        nng_ctx_send(job->ctx, job->aio)
                                                                                                                                            <-- async, returns immediately
                                                                                            |
                                                                                            v
                                                                                        send completes, NNG's worker
                                                                                        pool invokes JobRunner(job) again
                                                                                            |
                                                                                            v
                                                                                                                                    RunJob(): case kListening:
                                                                                                                                        ResetJob(job); job->state = kProcessing
                                                                                                                                        nng_ctx_recv(job->ctx, job->aio)
                                                                                                                                        (job is now free for
                                                                                                                                         the next request)
                                                                                                                                                                                   |
                                                                                                                                                                                   v
                                                                                                                                                                            reply arrives back at
                                                                                                                                                                            the client's nng_recv()
```

Two features of this design matter for the investigation. The 64-job pool means the server can service many requests concurrently, so a single slow handler elsewhere does not, by itself, starve `GetSimTime`'s own dedicated job slot, since NNG dispatches an incoming message to whichever context is currently in `kListening`.

But `methods_registry_`, the map every one of those 64 job callbacks reads via `RequestResponse()`'s `job->methods_registry->find(requested_method)` (`service_manager.cpp:291`), is mutated by `RegisterMethod()`, `UnregisterMethod()`, and `UnregisterAllMethods()` (`:256-284`) with no lock of any kind. The one lock this class does have, `service_manager_lock_`, a `std::shared_timed_mutex`, is acquired only in `Start()` and `Stop()` (`:184,235`), never around any registry mutation or lookup.

Two structurally different kinds of registration exist in `core_sim`. Individual methods are added one at a time with `RegisterMethod()`, called from roughly fifteen sites across `scene.cpp`, `simulator.cpp`, and every sensor and actuator that exposes a service, `camera.cpp`, `imu.cpp`, `gps.cpp`, `battery.cpp`, `airspeed.cpp`, `barometer.cpp`, `magnetometer.cpp`, `robot.cpp`, and the shared `actuator_impl.hpp`. `UnregisterMethod()`, the single-entry counterpart, is declared and defined but has zero callers anywhere in `core_sim` and thus, is dead code. `UnregisterAllMethods()` (`service_manager.cpp:281-284`), the wholesale operation that clears `methods_registry_` in one call, has exactly one call site in the entire tree, `Scene::Impl::UnregisterAllServiceMethods()` (`scene.cpp:889-890`).

Tracing that one call site upward pins down precisely when a full unregister happens. `Scene::Impl::UnregisterAllServiceMethods()` is called only from `Scene::Stop()` (`scene.cpp:394-401`), which is called only from `Simulator::Impl::StopScene()` (`simulator.cpp:199`), which is called only from `Simulator::StopScene()` (`simulator.cpp:134`), which is called only from `SimServer::StopScene()` (`simserver.cpp:99-102`). The registration side mirrors this exactly, `Scene::Impl::RegisterServiceMethods()` (`scene.cpp:827-836`, this is where `GetSimTime` is added) runs only from `Scene::Start()` (`scene.cpp:385-393`), reached only through `Simulator::Impl::StartScene()` (`simulator.cpp:193-197`), `Simulator::StartScene()` (`simulator.cpp:127-131`), and `SimServer::StartScene()` (`simserver.cpp:93-96`).

`SimServer::StartScene()`/`StopScene()` are, in turn, called from exactly two places in the whole ProjectAirSim tree. The first is `AUnrealSimLoader::LaunchSimulation()`/`TeardownSimulation()` (`UnrealSimLoader.cpp:59-137`), which are themselves called exactly once each, from `AProjectAirSimGameMode::StartPlay()`/`EndPlay()` (`ProjectAirSimGameMode.cpp:20-30`), Unreal Engine's own level-lifecycle hooks. Under the SITL stack's normal operation, a single level is loaded once per process and never transitions or restarts, so this path fires `RegisterServiceMethods()` once at process start and `UnregisterAllMethods()` once at process teardown, and never in between. This supports the belief that no scene reload happens after initial construction, though it is a conclusion reached by static tracing of the call graph, not yet by a live capture that confirms `EndPlay` was never hit mid-session.

The second call site is the one that matters. `SimServer::RegisterServiceMethods()` (`simserver.cpp:149-158`) registers `"LoadScene"` itself as a live RPC method, `/Sim/LoadScene`, bound to `SimServer::SimReloadSceneWithJSON()` (`simserver.cpp:160-234`). This is precisely the server-side method the ROS 2 bridge's `RequestLoadScene()` calls into, and the ROS bridge itself exposes it onward as its own `/projectairsim/load_scene` service (`projectairsim_ros2_cpp_node.cpp:1462-1468`). Unlike the Unreal level lifecycle, this method can be invoked at any time during a running session, by any connected client, with no UE-level scene transition involved at all.

`SimReloadSceneWithJSON()`'s body calls `StopScene()` (`UnregisterAllMethods()`, clearing the registry), then unloads and reloads the external Unreal scene, physics world, controllers, and tile manager, then calls `LoadScene()` and finally `RegisterServiceMethods()` again (`StartScene()`, repopulating the registry) before returning. This entire sequence runs inside a single service-method-handler callback, on one of the 64 concurrent job threads described in the flow chart above, the same threads that are, at that very moment, still able to receive and process a `GetSimTime` request from any other client on a different job slot. For the whole duration of that sequence, plausibly seconds for a scene of this complexity, `methods_registry_` is either empty or being actively mutated, while `projectairsim_ros2_cpp_node`'s clock timer keeps firing a fresh `GetSimTime` request every 5 ms regardless. `RegisterServiceMethods()`'s own comment at its call site, `"Register service methods each time a scene is loaded (since service manager unregisters them each scene unload)"` (`simulator.cpp:128-129`), confirms this repeated register-unregister cycle was an anticipated, designed-for pattern rather than an edge case nobody considered, it is exactly the mechanism `/Sim/LoadScene` is built to run through, every time it is called.

A collateral finding from the same reading, `UnregisterAllMethods()` and `UnregisterMethod()` both clear only `methods_registry_`, never the companion `method_parameters_registry_` that `ProcessRequest()` looks up via `method_parameters_registry.at(method_name)` (`service_manager.cpp:327`). `RegisterMethod()` (`:256-263`) populates both maps, but nothing ever prunes the parameters map on unregister, so across repeated `/Sim/LoadScene` cycles the two registries drift out of sync, growing a set of orphaned parameter-list entries that `methods_registry_` no longer has corresponding handlers for. This does not by itself explain a lost reply, since `RequestResponse()`'s `.find()` against `methods_registry_` fails cleanly first and returns an ordinary error response before `method_parameters_registry_` is ever consulted, but it is a real, separate correctness defect worth recording alongside the race.

This narrows the open question from §2.4 considerably. Whether the registry race actually fires during any of the six captured sessions no longer depends on finding an improbable UE-level scene restart, it depends on whether anything, this ROS node's own `/projectairsim/load_scene` service, the SITL launch scripts, or another client entirely, ever called `/Sim/LoadScene` while a session was running. None of the six sessions' logs have yet been checked specifically for this, since the check performed in §3.1 only confirmed `/projectairsim/load_scene` was not called during that one baseline session.

The full lifecycle traced above, from an empty UE level starting up, through a client connecting, to that client triggering a reload, is easier to follow as a call graph than as prose. The two flow charts below place every call site named in the four paragraphs above in the order each can actually fire, and mark the one window where `methods_registry_` is unpopulated or being mutated.

```
UE process lifecycle, fires once per process                       projectairsim_ros2_cpp_node, independent process
--------------------------------------------                       -------------------------------------------------
AProjectAirSimGameMode::StartPlay()
        |
        v
AUnrealSimLoader::LaunchSimulation()
        |
        v
SimServer::LoadSimulator()
    RegisterServiceMethods()
    (registers "LoadScene" itself)
        |
        v
SimServer::LoadScene()
        |
        v
LoadUnrealScene()
        |
        v
SimServer::StartSimulator()
    topic_manager_.Start(); service_manager_.Start()
    opens nng sockets, primes 64 job contexts
        |                                                           Node startup
        v                                                           connects nng_socket_services_ (REQ0)
StartUnrealScene()                                                  and nng_socket_topics_ (PAIR0)
        |                                                                   |
        v                                                                   v
SimServer::StartScene()                                             scene_config_ provided?
        |                                                            (current deployment: always yes)
        v                                                                   |
Simulator::StartScene()                                                     v
    Simulator::Impl::RegisterServiceMethods()                       world_->Initialize(client_, scene_config_path, ...)
    (sim-level methods)                                               -> World::Impl::LoadSceneConfig()
        |                                                              -> World::Impl::LoadScene()
        v                                                                   |
Scene::Start()                                                              v
        |                                                           Client::Impl::RequestLoadScene()
        v                                                              CancelAllRequests(); UnsubscribeAll();
Scene::Impl::RegisterServiceMethods()                                  topics_.StopReceiving()
    adds GetSimTime, ContinueForSimTime,                                    |
    ContinueUntilSimTime                                                    v
        |                                                           Request("/Sim/LoadScene", ...)
        |                                                              blocks in Wait() until the server replies
        |                                                                    |
        |                                                                    v
        |                                                           see second diagram below for everything that
        |                                                           happens here, the full server-side reload
        |                                                           cycle, methods_registry_ cleared and then
        |                                                           repopulated end to end, run here by this
        |                                                           node itself, not by a hypothetical other client
        |                                                                    |
        |                                                                    v
        |                                                           reply received, sent only after the server has
        |                                                           already re-added GetSimTime, see second diagram
        |                                                           scene_loaded_ = true
        |                                                                    |
        |                                                                    v
        |                                                           StartClockTimerIfReady()
        |                                                              creates clock_timer_, only if not already set
        |                                                                    |
        +--------------- both columns' registry writes are ------------->    v
                          complete by this point, steady state       Clock timer starts
                                                                      fires GetSimTime every 5 ms, forever
                                                                                    |
                                                                                    v
                                                                      (steady state, every 5 ms, own job slot)
                                                                      RequestResponse():
                                                                        job->methods_registry->find("GetSimTime")
                                                                        service_manager.cpp:291, unsynchronized read
```

The left column is the UE process's own lifecycle, unchanged from before. The right column is what actually happens in this exact deployment, where `scene_config_` is always provided, every single node startup runs its own `/Sim/LoadScene` call before it ever creates the clock timer, rather than the timer being a purely passive consumer of a registry someone else populated once. The branch into `Request("/Sim/LoadScene", ...)` is deliberately not redrawn here, it is identical to the reload cycle already traced in full in the second diagram below, so this diagram references it rather than duplicating it. Because `StartClockTimerIfReady()` runs strictly after `Initialize()` returns (`projectairsim_ros2_cpp_node.cpp:189-213`), this specific cold-start call to `/Sim/LoadScene` cannot race this node's own first `GetSimTime` request, the timer simply does not exist yet while it runs. The second diagram traces the same `/Sim/LoadScene` cycle as it can also occur later, mid-session, triggered by any connected client, including this same node's own `/projectairsim/load_scene` service (`LoadSceneRuntime()`, `projectairsim_ros2_cpp_node.cpp:1141-1173`), with a concurrent `GetSimTime` lookup from the steady-state loop landing on either side of, or inside, the window that opens in the middle.

```
Any connected client                          core_sim, job thread A                            core_sim, job thread B (any other slot)
(e.g. ROS /projectairsim/load_scene)          (services /Sim/LoadScene)                          (services GetSimTime, every 5 ms)
        |
        | Client::RequestLoadScene()
        v
  "/Sim/LoadScene" request  ----------------> RequestResponse() dispatch
                                               finds "LoadScene" in methods_registry_
                                                      |
                                                      v
                                               SimServer::SimReloadSceneWithJSON()
                                                      |
                                                      v
                                               SimServer::StopScene()
                                               -> Simulator::StopScene() -> Scene::Stop()
                                                      |
                                                      v
                                               Scene::Impl::UnregisterAllServiceMethods()
                                               service_manager_.UnregisterAllMethods()
                                               methods_registry_.clear()  -- NO LOCK
                                                      |
                                               *** methods_registry_ EMPTY ***  <-----------     concurrent, unsynchronized read
                                               window opens                                      GetSimTime request lands here
                                                      |                                                  |
                                                      v                                                  v
                                               unload/reload external UE scene,                  RequestResponse():
                                               physics world, controllers,                          job->methods_registry->find("GetSimTime")
                                               tile manager                                          service_manager.cpp:291
                                                      |                                                  |
                                                      v                                                  v
                                               SimServer::LoadScene(json_data)                   outcome depends on exactly when this read
                                                      |                                           lands relative to the window markers
                                                      v                                           traced in the middle column, see the
                                               SimServer::RegisterServiceMethods()                three outcomes listed below the diagram
                                               re-adds "LoadScene" itself and other
                                               sim-level methods -- GetSimTime is
                                               STILL absent at this point
                                                      |
                                                      v
                                               load_external_scene_func()
                                               start_external_scene_func()
                                               UE actor/world spawn, likely the
                                               SLOWEST step of the whole cycle
                                                      |
                                                      v
                                               SimServer::StartScene()
                                                      |
                                                      v
                                               Simulator::StartScene() -> Scene::Start()
                                                      |
                                                      v
                                               Scene::Impl::RegisterServiceMethods()
                                               re-adds GetSimTime etc  -- NO LOCK
                                                      |
                                                      v
                                               *** methods_registry_ repopulated ***
                                               window closes
```

```
Outcome E1 -- the right-column read lands before the window opens or after it closes:
    find() succeeds normally, handler runs, reply sent.

Outcome E2 -- the right-column read lands inside the window, but not concurrently with
an actual .clear()/insert() instruction on the middle column:
    find() cleanly misses, "not supported" error reply. NOT a hang by itself.

Outcome E3 -- the right-column read overlaps the actual mutating instructions of
.clear() or an insert() inside RegisterMethod() on the middle column:
    unsynchronized concurrent read/write on the same std::map, undefined behaviour
    by the C++ standard. Plausible source of a lookup that never returns, not yet
    reproduced.
```

The window drawn here is wider than the earlier version of this diagram showed. `GetSimTime` is absent from `methods_registry_` for the entire span from `StopScene()` at the top of `SimReloadSceneWithJSON()` through `StartScene()` at the very end (`simserver.cpp:167-211`), and that span includes `load_external_scene_func()`/`start_external_scene_func()`, the callbacks into Unreal that spawn and start the new level's actors, almost certainly the single slowest step in the whole cycle. A `GetSimTime` request from a second client can therefore land inside this window for a duration measured in real wall-clock seconds, not nanoseconds, it is not a narrow instant that is merely plausible to hit, it is a broad interval that is easy to hit if a second client is polling at all during a reload. Within that broad interval, most of the time a lookup simply finds nothing and returns the clean `E2` error, the true `E3` hazard is confined to the much narrower instants of the initial `.clear()` and each individual `RegisterMethod()` insert, of which there are several, one for every sim-level and scene-level method being re-added, each one a separate opportunity for a concurrent read to race a write on the same unlocked `std::map`. A second, distinct observation from this reading, `SimServer::RegisterServiceMethods()` re-adds `"LoadScene"` itself well before `GetSimTime` comes back, so a second `/Sim/LoadScene` call issued by another client while the first reload is still inside the external-scene-loading step would be accepted and would begin a nested reload cycle concurrently with the first, this is a further correctness question worth flagging but is not pursued further here since it is not required to explain a lost `GetSimTime` reply.

Two things the second diagram makes explicit that the prose above does not. First, the empty-level startup path in the first diagram and the client-triggered reload path in the second both terminate in the exact same two calls, `UnregisterAllMethods()` then `RegisterServiceMethods()`, so anything true of one registry-clearing window is true of the other, the only difference is that the startup path's window is crossed once at process start before any client is likely connected, while the reload path's window can open at any point in a live session with the clock timer already running against it.

Second, the diagram separates two distinct failure modes that the prose treats together. A `find()` that lands cleanly before the window opens or after it closes, outcome `E1`, succeeds normally, and a `find()` that lands inside the window but not concurrently with an actual `.clear()`/insert instruction, outcome `E2`, fails cleanly with an ordinary error reply, that is not a hang. The only outcome that plausibly produces a lost reply is `E3`, a `find()` whose read overlaps the actual mutating instructions of `.clear()` or the map insertions inside `RegisterMethod()`, an unsynchronized concurrent read and write on the same `std::map` is undefined behaviour by the C++ standard regardless of how narrow the overlap is, and undefined behaviour is exactly the kind of failure that can manifest as a lookup that never returns rather than a clean crash. This is why the instrumentation candidates in §2.4 target the boundaries of the window, the `UnregisterAllServiceMethods()`/`RegisterServiceMethods()` calls and the `/Sim/LoadScene` entry/exit, rather than the window's contents, the goal is to catch a `GetSimTime` request timestamped inside that interval, not to catch the race itself.

A lone client cannot race itself through this mechanism, and this deployment, as configured, has only one client. `Client::Impl::Request()`'s `Wait()` blocks the calling thread until the server's reply arrives, and the diagram above shows that reply is sent only after `Scene::Impl::RegisterServiceMethods()` has already re-added `GetSimTime`, so the thread that issued `/Sim/LoadScene` cannot issue its next request, whatever that request is, until the registry is already whole again. `projectairsim_ros2_cpp_node` reinforces this at the ROS layer, it runs on a `SingleThreadedExecutor`, so the callback blocked inside `RequestLoadScene()`, whether the constructor's initial call at line 189 or the `/projectairsim/load_scene` handler `LoadSceneRuntime()` at line 1149, cannot be interleaved with the clock timer's own `PublishClock()` callback, only one of this node's own callbacks runs at a time. A `GetSimTime` request generated by this same node's own timer during a reload it itself triggered is therefore structurally impossible, both the transport-level blocking and the executor's own serialization rule it out independently of each other.

The race requires a second, independently connected client issuing `GetSimTime` or any other service call while `/Sim/LoadScene` is running on some other job thread, and whether that second client exists at all is the question this reinvestigation actually turned on. `ros_ws/src/controllers/launch/sitl2.launch.py` launches exactly one `projectairsim_ros2_cpp_node`, its own comment (`:71-73`) describing it as "the primary client that loads" the scene, and ArduPilot SITL is launched afterward as a separate action. `docs/controllers/ardupilot.md` (`:31,45`) confirms ArduPilot talks to the simulator over a UDP/IP socket on a port such as `9002`, not through `core_sim`'s NNG service channel at all, so it is not a second `core_sim` client regardless of when it starts relative to a reload. No other script or node under `sitl_ws` or `ardu_ws` was found constructing a Project AirSim client. Under this launch configuration, as it stands today, no second `core_sim` client has been identified, so the registry-clearing race, while a genuine, confirmed latent defect in `core_sim`'s unsynchronized `methods_registry_`, currently lacks a demonstrated trigger in this specific deployment, it cannot yet be assumed to be the cause of the captured stalls, that assumption would require either an as-yet-unfound second client, or evidence that the single client's own request pattern somehow violates the one-outstanding-request invariant this whole design leans on.

One quirk in that request pattern is worth recording even though it does not itself explain a hang. `CancelAllRequests()` (`Client.cpp:427-446`), called at the top of every `RequestLoadScene()` (`Client.cpp:628`), including the very first one at cold start when nothing is pending, always sends a `"CancelRequest"` request via `RequestPriorityAsync()` and waits for its reply before `RequestLoadScene()` goes on to send `/Sim/LoadScene` itself. No `core_sim` method named `"CancelRequest"` is registered anywhere in the tree, so this call is answered by `RequestResponse()`'s clean not-found path every single time, an extra harmless round trip on every reload, not a bug, but part of the exact request sequence a future instrumentation pass should expect to see on the wire.

Given that the registry race currently lacks a demonstrated second client, the three `RunJob()` candidates below are, on present evidence, the more probable explanation for the captured stalls, since none of them require more than the one client this deployment actually has. Reading `RunJob()` (`service_manager.cpp:405-528`) in full surfaces three further, independent candidates for a silently lost reply, none of which require any registry mutation at all. First, every `nng_aio_result(job->aio)` check in the state machine, on the receive path (`:421-423`) and the send path (`:443-445`), is followed by a commented-out `LogError` call and no other handling, so if a previous `nng_ctx_send()` for this job actually failed at the NNG layer, for instance because the underlying pipe to a specific client had a transient issue, the job proceeds exactly as if the send had succeeded, silently discarding the fact that a client's reply never left the server, with nothing logged anywhere to show it happened. Second, `RunJob()`'s very first line, `if (job->parent_is_alive->load() == false) return;` (`:406`), causes the job to return without calling `nng_ctx_recv()` or `nng_ctx_send()` again if `is_alive_` is ever observed false mid-flight, permanently halting that job's state machine until the next `Start()` recreates it, currently only reachable through `Stop()` but a second latent mechanism worth keeping in mind. Third, if `nng_msg_alloc()` fails while packing a response (`:496-505`), the code frees the message it just failed to allocate and then proceeds unconditionally to `nng_aio_set_msg()` and `nng_ctx_send()` on that same pointer, a use of a freed or null message that is undefined behaviour under memory pressure rather than a clean failure path.

Collecting all of this together, the next debugging session has three concrete, falsifiable threads to pursue before writing any fix, ordered by how well-supported each currently is: whether a second `core_sim` client, not yet identified anywhere in this deployment's launch stack, was ever connected during any of the captured stalls, since without one the registry race has no demonstrated trigger here; whether re-enabling the currently commented-out `LogError` calls inside `RunJob()` surfaces a send or receive failure on the job that was supposed to answer a stuck `GetSimTime` request, which needs no second client and is on present evidence the more probable avenue; and, only if a second client is found, whether `/Sim/LoadScene` was invoked by it during a captured stall. This document does not instrument any of these yet, per this session's scope, that is deferred to the next request.

### 2.3 Why simulation time is a service and not a topic

This section is background for possible future work, publishing simulation time as a topic rather than a service, and is recorded here purely as documentation of the current implementation and simulation design. It does not evaluate or design that future work.

Project AirSim's server exposes remote-readable state through two structurally distinct mechanisms, and `TopicManager`, not `ServiceManager`, is the one every sensor and actuator stream uses. `TopicManager::Impl` (`core_sim/src/topic_manager.cpp`) owns a second `nng` socket, `topic_socket_`, opened as a `pair0` socket, entirely separate from `ServiceManager`'s `nng_rep0` socket described in §2.2.

A simulation object that wants to expose continuously-changing data calls `RegisterTopic()` once, at construction or `OnBeginUpdate()`, and then calls `PublishTopic()` every time it has a fresh value, with no client ever having to ask. The flow chart below traces this path using `Imu::Impl`, one of the many sensor classes that follow this pattern, as the concrete example, alongside the corresponding client-side reception path already introduced in §2.1's `TopicReceiveThreadProc()`.

```
Imu::Impl                          TopicManager::Impl                    NNG topic_socket_ (pair0)              Client::Impl (subscriber side)
(once, in OnBeginUpdate())                                                                                       Topics::Subscribe() already
                                                                                                                   registered a callback for this
      |                                                                                                          topic path, before any of this,
      | RegisterTopic(imu_kinematics_topic)                                                                      via the generic
      v                                                                                                          DiscoverAndSubscribe() loop
                                    lock(manager_lock_)                                                          covered in the prior answer on
                                    topic_table_[path] = TopicBlock(topic, ...)                                  topics vs. services.
                                    unlock

(every scene tick, in Update())
      |
      | build ImuMessage(time_stamp, orientation, angular_velocity, linear_acceleration)
      | PublishTopic(imu_kinematics_topic, imu_msg)
      v
                                    if client_authorization_.IsAuthorized():
                                        send_dispatcher_.dispatch([this, topic, message] { Send(topic, message); })
                                            (async, off the calling thread, no reply expected or waited for)
                                            |
                                            v
                                    Send(): serialize, nng_send(topic_socket_, ...)
                                            |
                                            v
                                                                                    travels to every connected client
                                                                                            |
                                                                                            v
                                                                                                                     TopicReceiveThreadProc() (Topics.cpp)
                                                                                                                     blocks on nng_recv(nng_socket_topics_)
                                                                                                                     dispatches to the registered
                                                                                                                     topic_callback for "imu_kinematics"
                                                                                                                            |
                                                                                                                            v
                                                                                                                     HandleProjectAirSimMessage()
                                                                                                                     in projectairsim_ros2_cpp_node.cpp
                                                                                                                     publishes sensor_msgs::msg::Imu
                                                                                                                     on the ROS 2 side
```

Two things distinguish this path from `GetSimTime`'s request-response path in §2.1 and §2.2. First, `PublishTopic()` never blocks its caller and never waits for an acknowledgement, `send_dispatcher_.dispatch(...)` queues the send and returns immediately, so a sensor's `Update()` call is never at risk of hanging the way `RequestSimTime()` is.

Second, and more relevant to why this document exists, `RegisterTopic()`'s own access to `topic_table_` is properly synchronised with a `std::shared_timed_mutex` (`manager_lock_`, acquired in `RegisterTopic()`, `SubscribeTopic()`, `UnregisterTopic()`, and `ContainsTopic()`), unlike `ServiceManager::Impl::methods_registry_`, which §2.2 already established has no locking at all. This is a second, independent piece of evidence, alongside the git-archaeology finding in §4.2, that the request-response machinery `GetSimTime` depends on received less careful engineering attention than the topic-publishing machinery every other sensor stream uses.

Every caller of `TopicManager::RegisterTopic()` in `core_sim/src` is a per-object sensor or actuator, `sensors/camera.cpp`, `sensors/imu.cpp`, `sensors/gps.cpp`, `sensors/lidar.cpp`, `sensors/barometer.cpp`, `sensors/radar.cpp`, `sensors/magnetometer.cpp`, `sensors/battery.cpp`, `sensors/airspeed.cpp`, `sensors/distance_sensor.cpp`, `actuators/rotor.cpp`, `joint.cpp`, `actor/robot.cpp`, and `actor/env_actor.cpp`. `Scene`, which owns `sim_time_` and is the object `GetSimTime` reads from, is conspicuously absent from that list.

`Scene::Impl` does hold a `topic_manager_` member, but its only uses of it are to pass the reference down to `Robot` and `EnvActor` constructors, so that *they* can register *their own* sensor topics (`scene.cpp:1398,1436`), and to toggle a topic-published logging callback (`scene.cpp:1114-1122`). `Scene` itself never calls `RegisterTopic()` or `PublishTopic()` for `sim_time_`.

Instead, `Scene::Impl::RegisterServiceMethods()` (`scene.cpp:827-836`) registers `GetSimTime` purely as a request-response method, alongside `ContinueForSimTime` and `ContinueUntilSimTime` (`scene.cpp:848-859`), which are step-and-query style calls, a client asks the server to advance simulation time by a given amount or to a given target and expects a reply once that is done.

`GetSimTime` was evidently designed as the read-side counterpart of that same on-demand, request-response pattern, not as a continuously streamed quantity, which is a plausible design rationale for why it was never given a topic, on-demand queries are what request-response is for, and `ContinueForSimTime`/`ContinueUntilSimTime` could not sensibly be topics at all, since they are commands, not readable state.

Publishing simulation time as a topic instead of, or in addition to, a service is one possible way to remove `/clock`'s dependency on the request-response path this document's root cause concerns entirely, `Scene` could call `topic_manager_.RegisterTopic()` for a `sim_time` topic once and `PublishTopic()` once per tick, the same way `Imu::Impl::Update()` does, and `projectairsim_ros2_cpp_node` could subscribe to it through the same generic `DiscoverAndSubscribe()`/`CreateHandler()` path already used for every other sensor, rather than through `PublishClock()`'s dedicated polling timer. This document records that option here as background for future work, and does not size, design, or evaluate it further.

### 2.4 What remains to investigate

The four threads originally listed here, re-enabling `RunJob()`'s commented-out `LogError` calls, searching for a second `core_sim` client, checking `/Sim/LoadScene` timing against a captured stall, and determining whether a request ever left the client, are now resolved. §3.5's end-to-end instrumentation and its three captures ruled out every server-side and registry-race candidate directly, no `GetSimTime` request ever reached `RunJob()` in any capture, and identified the actual trigger, the uninitialized `bool fis_canceled_` member on `TAsyncResultProviderBase` (`AsyncResultInternal.h:34-67`), which is read before a freshly constructed request is ever sent and, for the captured `GetSimTime` request, happened to read non-zero from unrelated heap contents. §4.3 and §4.4 give the full mechanism and the fix. What remains is implementing that fix and a validation session confirming it, tracked in §4.4's closing paragraph, not further investigation of this section's original four threads.

## 3. Investigations

Six log-capture sessions were recorded during this investigation, using the `djinn start sitl2` stack. All six are preserved under `context/artefacts/project-airsim-clock-publication-bug/`, one sub-directory per session named by its capture timestamp, each containing `airsim.log` (the Project AirSim server's own log) and `sitl_bridge.log` (the combined stdout of every ROS 2 node launched by `sitl2.launch.py`, including `projectairsim_ros2_cpp_node`). All paths below are given relative to `context/artefacts/project-airsim-clock-publication-bug/`.

### 3.1 Baseline capture, `20260820_101006/`

This was the first capture taken. No logging had yet been added beyond what `projectairsim_ros2_cpp_node.cpp` already carried. The purpose was to establish where the ROS 2 `/projectairsim/load_scene` service fit into scene bring-up, since the initial hypothesis was that the clock timer's startup guard was failing.

The log showed the scene loading successfully through a different path than initially suspected, the constructor's `scene_config` launch parameter (`sitl2.launch.py` line 87, `"scene_config": "scene_ardu_copter.jsonc"`) drives a direct load at construction time via `world_->Initialize(...)`, not the `/projectairsim/load_scene` ROS 2 service, which exists only for a secondary, non-primary-client use case and was never invoked in this session. The log further showed `"Resolved Project AirSim clock parent topic: /Sim/StonePineForestArduCopter"` immediately after scene load, meaning `StartClockTimerIfReady()`'s guard, `!scene_loaded_ || publish_clock_period_sec_ <= 0.0 || clock_timer_`, could not have been the obstacle, since `scene_loaded_` was already true and `publish_clock_period_sec_` was `0.005` from the launch file.

A live `ros2 topic info /clock -v` and `ros2 topic hz /clock` run against the stack at this point showed the publisher correctly advertised with compatible QoS against both of its subscribers, yet zero messages delivered. A further live test, calling the built-in `list_parameters` service on `projectairsim_ros2_cpp_node`, also hung and timed out, which was the first evidence that the stall was not specific to the clock code path at all, but affected the node's single-threaded `rclcpp` executor as a whole, since `list_parameters` shares no code or state with anything clock-related.

`main()`'s use of plain `rclcpp::spin(node)` (`:1420-1423`) confirmed a `SingleThreadedExecutor` was in use, under which one permanently blocking callback anywhere in the node freezes every other timer and service, while topics fed by the Project AirSim client SDK's own background subscription thread, bypassing the executor entirely, continue to update normally. This fully explained why sensor topics kept flowing while `/clock` and every ROS 2 service on the node went silent together.

### 3.2 Service-level instrumentation, `20260820_102357/` and `20260820_103204/`

To identify which callback was stuck, `RCLCPP_INFO` logging was added at the start and at both successful and exceptional completion of every service callback, by instrumenting the single shared wrapper template `CreateService<>()` (`projectairsim_ros2_cpp_node.cpp:1183-1201`) rather than each of the 25 individual service lambdas, since every service, including the four group services, is registered through that one template and its `try`/`catch` already surrounds every callback's single exit point.

```cpp
RCLCPP_INFO(get_logger(), "%s: request received", name.c_str());
try {
    fn(request, response);
    RCLCPP_INFO(get_logger(), "%s: request completed", name.c_str());
} catch (const std::exception& error) {
    SetSuccessIfPresent(*response, false);
    RCLCPP_ERROR(get_logger(), "%s failed: %s", name.c_str(), error.what());
    RCLCPP_INFO(get_logger(), "%s: request completed (exception)", name.c_str());
}
```

`20260820_102357/` was an intermediate capture taken before this change had been rebuilt in, and shows the same baseline symptoms as §3.1 with no new information. `20260820_103204/` was captured after rebuilding with the change above. It contains zero occurrences of either `request received` or `request completed`, across a session lasting well over a minute, confirming that no ROS 2 service was ever called during that entire session.

Since `/clock` still failed to publish live in this same session (`ros2 topic hz /clock` timing out again), this ruled out the working hypothesis that some *other* service call was stuck and starving the executor, since no service call had been made at all. That redirected the investigation to the clock timer's own callback, `PublishClock()`, as the most likely thing occupying the executor, since it is the one executor-dispatched callback armed early and fired at high frequency, 200 Hz, with nothing else competing for the single thread in this session.

### 3.3 Clock-timer guard instrumentation, `20260820_104817/`

`StartClockTimerIfReady()`'s compound guard was split into three independent checks, each logging its own `RCLCPP_WARN` naming which condition failed (`:1108-1123` at the time), to make the guard's outcome unambiguous rather than a single silent `return`. This capture showed exactly one warning, `"StartClockTimerIfReady: clock_timer_ already created"`, and no warnings for the other two conditions.

At first reading this looked like evidence the timer was never created, but tracing the call sequence in the constructor showed the opposite. `StartClockTimerIfReady()` is called twice, once inside `DiscoverAndSubscribeIfReady()` (constructor line 212) and once directly immediately after (constructor line 213). Since `scene_loaded_` was already true by the time `DiscoverAndSubscribeIfReady()` ran, its internal short-circuit skipped straight to calling `StartClockTimerIfReady()` for the first time, at which point `clock_timer_` was still null and the guard passed cleanly, creating the timer, silently, since no success-path log existed yet at that point. The second, redundant call at line 213 then correctly found `clock_timer_` already set and exited, producing the one warning seen.

Because the three checks in this version of the code are independent `if` statements rather than `else if`, the absence of the other two warnings on that same call further confirms `scene_loaded_` and `publish_clock_period_sec_` were both already satisfied. A success-path log, `"StartClockTimerIfReady: clock_timer_ created (period %f s)"` (`:1124-1128` at the time), was added immediately after this capture to close the ambiguity for future sessions.

### 3.4 Clock-callback instrumentation, `20260820_105619/`

Logging was added directly around `PublishClock()` and `RequestSimTime()`, the two functions that had not yet been instrumented, using `RCLCPP_INFO_THROTTLE` at a 5000 ms window to match the file's existing `RCLCPP_WARN_THROTTLE` style, since these run at 200 Hz and would otherwise flood the log, while still guaranteeing the very first invocation logs immediately regardless of the throttle window.

```cpp
void PublishClock() {
    RCLCPP_INFO_THROTTLE(get_logger(), *get_clock(), 5000, "PublishClock: tick received");
    ...
    clock_publisher_->publish(clock_msg);
    RCLCPP_INFO_THROTTLE(get_logger(), *get_clock(), 5000, "PublishClock: tick completed, sec=%lld", ...);
}
```

and, inside `RequestSimTime()`, a log immediately before and after the `client_->Request(...)` call. This capture showed `PublishClock: tick received`, followed immediately by `RequestSimTime: sending /Sim/StonePineForestArduCopter/GetSimTime request`, and nothing further, ever, for the rest of the session. No `tick completed`, no `request returned`, no `WARN_THROTTLE` of any kind.

This was the first direct evidence that the hang is inside `RequestSimTime()` specifically, on its very first invocation, rather than anywhere in the timer setup or scene loading paths already ruled out in §3.1 to §3.3.

### 3.5 Mutex-entry and end-to-end instrumentation, root cause confirmed, `20260820_110321/` through `20260820_182659/`

A further log line, `"RequestSimTime: Entered after mutex"`, was added immediately after `std::lock_guard<std::mutex> lock(client_mutex_);` and before the `client_->Request(...)` call itself (`:820-828` in the current file, reproduced in full in §2.1). This capture showed the following sequence and then silence for the remainder of the session.

```
StartClockTimerIfReady: clock_timer_ created (period 0.005000 s)
StartClockTimerIfReady: clock_timer_ already created
PublishClock: tick received
RequestSimTime: sending /Sim/StonePineForestArduCopter/GetSimTime request
RequestSimTime: Entered after mutex
```

This pinpoints the stall precisely, `client_mutex_` was acquired without contention, so the hang is not a wait on that mutex, and the very next line of code, `client_->Request(method, json::object(), &message_response)`, is the last thing that ran.

Combined with the client-library architecture traced in §2.1, this is exactly consistent with the `ResponseReceivingThreadProc()` retry-forever behaviour, the request was successfully queued and sent by `RequestSendingThreadProc()`, but the reply, for whatever reason, never arrived, and the receiving thread's `NNG_ETIMEDOUT` branch has been silently retrying `nng_recv()` ever since, with nothing left to log because the code genuinely has nothing further to say until a reply, or a real error, arrives.

A live check performed while writing this document, well after this capture, confirmed `/clock` still had not recovered, consistent with an unbounded rather than a five-minute stall, since a five-minute bound would have long since expired and either succeeded or logged a timeout warning that does not exist anywhere in any of the six captures.

To pin down where past `client_->Request(...)` a reply actually goes missing, logging was extended through the complete request/response path on both sides of the wire, the client's sending thread and receiving thread in `Client.cpp`, the server's 64-job `RunJob()` pool and the `methods_registry_` mutation functions in `service_manager.cpp`, and the scene-reload sequence in `simserver.cpp`, all sim-time-stamped via `SimClock::Get()->NowSimNanos()` so events on both sides of the wire can be correlated. `Client::Impl::SendRequest()` (`Client.cpp:935-974`) now logs immediately before and after `nng_send()`. `RequestSendingThreadProc()` (`:716-793`) now logs when it dequeues an entry from `list_pending_request_entry_` and again once `SendRequest()` returns, or, on the branch that turned out to matter, when it finds the dequeued entry already marked canceled and skips `SendRequest()` entirely. `ResponseReceivingThreadProc()` (`:795-930`) now logs its dequeue, every `nng_recv()` call, and, critically, the `NNG_ETIMEDOUT` branch itself, which previously logged nothing at all.

On the server, `RunJob()` (`service_manager.cpp:437-615`) gained a `job_index` field and logging at every previously-silent branch, request-received and response-sent lines naming the `request_id` and method, and `RegisterMethod()`/`UnregisterAllMethods()` (`:260-308`) now log every registry mutation with a sim-time timestamp, so any capture can show directly whether a stalled request's `sim_time_ns` falls inside a registry-clearing window. This instrumentation is purely additive, no behaviour was changed, and the two known latent server-side bugs already documented in §2.2, the `nng_msg_alloc()` failure path and the `method_parameters_registry_` desync, are logged where they occur but were left unfixed, out of scope for a logging pass.

The log capture, `/ws/logs/20260820_182659/` pinpointed the root cause of the problem. The full sequence for the node's first two requests, `CancelRequest` (`request_id=0`) and `/Sim/LoadScene` (`request_id=1`), is unremarkable and clean, `sitl_bridge.log:151-162`, `Client: sending request_id=0 ...` through `nng_recv() OK for request_id=1, 55 bytes received, completing the pending request`, both requests sent and answered in under 40 ms. Five seconds later, at `18:27:19:239` (`sitl_bridge.log:191-193`), `PublishClock`'s first tick fires, `RequestSimTime` sends `/Sim/StonePineForestArduCopter/GetSimTime`, and enters the mutex, exactly the sequence established in every prior capture. The very next line from the node, at the same timestamp (`:205`), is `RequestSendingThreadProc: dequeued method='/Sim/StonePineForestArduCopter/GetSimTime' was already canceled, skipping SendRequest()`. `nng_send()` is never called for this request. `airsim.log` for this same capture confirms it, exactly the same two `request received` lines as the second capture and nothing else, `GetSimTime` never arrives, because it was never sent. This is the last log line the node ever produces, `sitl_bridge.log` has grown to 1984 lines since, spanning well over an hour of continued `ardupilot_sitl` and `SimServer` activity, with zero further output from `projectairsim_ros2_cpp_node`, confirming the block is permanent rather than a slow eventual recovery.

`RequestSendingThreadProc()`'s dequeue loop (`Client.cpp:716-793`) explains why this hangs forever instead of failing fast. The loop checks `pasyncresultprovider_message->FIsCanceled()` (`:761`) before calling `SendRequest()`. `FIsCanceled()` (`AsyncResultInternal.h:40`) reads a plain `bool fis_canceled_` member. Only one place in the whole tree sets this member directly: `TAsyncResultProviderBase::Cancel()` (`:52`, `fis_canceled_ = true`). A caller must hold an `AsyncResult`/`TAsyncResult<T>` handle to call it. `Client::Impl::CancelAllRequests()` never touches `fis_canceled_` directly either. It calls `SetDone(Status::Canceled)` on each pending entry, then clears `list_pending_request_entry_` outright. That clear would have stopped `RequestSendingThreadProc()` from ever dequeuing this entry. The `GetSimTime` entry was still in the list to be dequeued, so `CancelAllRequests()` was not the cause. Nothing in `RequestSimTime()`'s call chain calls `.Cancel()` on this request's handle either, so that path is ruled out too. The remaining explanation is the constructor. `TAsyncResultProviderBase`'s constructor (`:35-36`) initializes `cv_done_`, `fis_done_(false)`, `mutex_`, and `status_(Status::InProgress)`. It never initializes `fis_canceled_`. `TAsyncResultProvider<Message>`'s own constructor (`:110-112`) only initializes `fn_response_callback` and delegates to the base. It never touches `fis_canceled_` either. So `fis_canceled_` is read uninitialized on every `TAsyncResultProvider<Message>` this client constructs, a plain `bool` with no default member initializer, whose value on construction is whatever byte was already sitting in the heap memory `new` returned. This is undefined behaviour.

An uninitialized read being undefined does not mean its value varies from run to run. The C++ standard gives no guarantee about the byte, but a fixed compiled binary reading a fixed heap address, reached by a fixed sequence of prior allocations and frees, will very often return the exact same byte every single time it runs. Every capture in this document used the same scene file, `scene_ardu_copter.jsonc`, the same fixed set of 12 topics, and the same startup order, so the sequence of heap allocations between the last time this memory was written and the moment `GetSimTime`'s result object claims it is identical on every run. Determinism here comes from the fixed input and the fixed binary, not from any guarantee in the language. To find exactly what that fixed sequence contains, and whether `LoadScene` and `GetSimTime` actually differ anywhere else, the full call stack of both services was traced from the node's construction of its `client_`/`world_` objects down to server-side registration, shown below.

```
Node construction (shared, once)
    client_ = make_shared<Client>()  (node.cpp:144)
    world_  = make_shared<World>()   (node.cpp:145)
    client_->Connect(...)            (node.cpp:175)
        |
        | world_->Initialize(client_, scene_config_path, ...)  (node.cpp:188-190)
        v

LOADSCENE (request_id=1, sent OK)                                   GETSIMTIME (request_id=2, never sent)
World::Impl::Initialize()                                           [5 seconds after LoadScene below completes]
    |                                                               clock_timer_ fires every 5 ms  (node.cpp:239)
    | LoadSceneConfig()                                                 |
    v                                                                   | RequestSimTime()  (node.cpp:813)
World::Impl::LoadScene(json_scene, delay)  (World.cpp:1218)             v
    |                                                               client_->Request(parent_topic+"/GetSimTime", ...)
    | pclient_->RequestLoadScene(scene_config)  (World.cpp:1277)        (node.cpp:828) -- no World.cpp wrapper, called directly
    v
Client::Impl::RequestLoadScene()  (Client.cpp:623)
    |
    | CancelAllRequests()  (:628) -- queue empty, so:
    |     RequestPriorityAsync("CancelRequest")  (:444)
    |         new TAsyncResultProvider<Message> #1  (:705)
    |         SendRequest() direct, bypasses queue
    |         sent, answered, freed  (request_id=0)
    | UnsubscribeAll()  (:629)
    | topics_.StopReceiving()  (:631)
    v                                                                   |

Request("/Sim/LoadScene", ...)  (:633)                                  |
    |                                                                   v
    | Client::Impl::Request()  (:581)                               Client::Impl::Request()  (:581)  <-- identical code
    v                                                                   |
RequestAsync()  (:584)                                                  | RequestAsync()  (:584)  <-- identical code
    |                                                                   v
    | new TAsyncResultProvider<Message> #2  (:601)                  new TAsyncResultProvider<Message> #3  (:601)
    | queued in list_pending_request_entry_                             queued in list_pending_request_entry_
    v                                                                   |

#2 allocated ~40 ms after #1 freed                                      v
    little intervening heap churn                                   #3 allocated ~5 s after #2 freed, only after:
                                                                        topics_.StartReceiving()  (Client.cpp:639)
                                                                        GetTopicInfo() parses 12 topics  (Client.cpp:564)
                                                                        CreateServices(), CreateActionServer()  (node.cpp:207-208)
                                                                        DiscoverAndSubscribeIfReady() bridges 12 topics  (node.cpp:210)
                                                                        StartClockTimerIfReady() builds clock_timer_
                                                                        fixed sequence every run: scene file names 12 topics every time
    |                                                                   |
    v                                                                   v

RequestSendingThreadProc dequeues #2  (:761)                        RequestSendingThreadProc dequeues #3  (:761)
    FIsCanceled() reads false, freshly allocated                        FIsCanceled() reads true, chunk last held by
                                                                        the heap churn above
    |                                                                   |
    v                                                                   v
SendRequest() -> nng_send()  runs normally                          SendRequest() SKIPPED, nng_send() never runs
    |                                                                   X-- request never leaves the client, ever
    -------------------------------> to server
    |
    v

Server: "LoadScene" registered once at cold start                   Server: "GetSimTime" re-registered on every
    simserver.cpp:155, SimServer level                                  `/Sim/LoadScene` reload, scene.cpp:833, Scene level
    |                                                                   |
    | RunJob receives id=1, SimReloadSceneWithJSON() runs               | RunJob never receives anything for this request
    v                                                                   v
response sent, #2 completes via SetDoneResult()                     (nothing -- Wait() blocks forever, no SetDone())
```

The trace confirms `LoadScene` and `GetSimTime` share the exact same client-side allocation code, `Client::Impl::Request()` calling `RequestAsync()` calling `new internal::TAsyncResultProvider<Message>(...)` (`:581-621`). Neither service has a special-cased or differently constructed result object anywhere in `Client.cpp`, `World.cpp`, `scene.cpp`, or `simserver.cpp`. The only real differences are structural: `LoadScene` is wrapped in its own `CancelAllRequests()`/`UnsubscribeAll()`/`StopReceiving()`-`StartReceiving()` sequence and is the second heap-allocated result object of the session, while `GetSimTime` is a bare `Request()` call issued five seconds later, after the deterministic, single-threaded burst of topic listing, ROS publisher and subscription construction, and service/action-server setup that `DiscoverAndSubscribeIfReady()` and its neighbours run for exactly 12 topics, every time, because the scene file names exactly 12 topics every time. That burst is what last wrote to whatever heap chunk `#3` reuses. Pinning the exact object that wrote the specific non-zero byte would need a runtime tool this container does not have, `valgrind` or `ASan`, but the mechanism itself needs no such tool to establish: a fixed binary replaying a fixed allocation sequence reuses the same memory the same way every time, which is why this failure reproduces identically across every capture in this document rather than appearing intermittently as a truly random bit-flip would.

This turns into a permanent hang, not a fast, visible failure, for one more reason. The `else` branch that handles an already-canceled dequeued entry (`Client.cpp:780-785`) only logs and falls through to `Release()`. It never calls `SetDone()` on the entry. The caller, `RequestSimTime()` via `Client::Impl::Request()` (`:581-595`), is blocked in `async_result.Wait()` (`AsyncResultInternal.h:53-58`). `Wait()` loops on `cv_done_.wait(ul)` while `!fis_done_`, and `fis_done_` is only ever set by `SetDone()`. `SetDone()` is never called on this entry, on this control-flow path, so `Wait()` cannot return. Not on a timeout. Not on a cancellation. Not on a send failure. None of those paths run, because the entry is discarded before any of them are reached. This is a second, independent bug, separate from the missing `NNG_ETIMEDOUT` handling already fixed in §4.4. It is the one actually responsible for every stall captured in this document. The §4.4 fix cannot help here: the request never reaches `nng_send()`, so it never reaches `nng_recv()` either, and the `NNG_ETIMEDOUT` branch never runs.

## 4. Root Cause and Solution

### 4.1 What the evidence establishes

The investigation across §3.1 to §3.5 establishes, with direct log evidence at each step, that the single-threaded `rclcpp` executor of `projectairsim_ros2_cpp_node` is not itself malfunctioning, that the clock timer is created correctly and fires correctly, and that the stall is a genuine, indefinite block inside the very first `client_->Request()` call `RequestSimTime()` ever makes to `<scene topic>/GetSimTime`. §3.5's end-to-end instrumentation traced this block to its exact source, an uninitialized `bool fis_canceled_` member on `TAsyncResultProviderBase` (`AsyncResultInternal.h:34-67`, constructor at `:35-36`), read by `RequestSendingThreadProc()`'s `FIsCanceled()` check (`Client.cpp:761`) before a request is ever sent, whichever heap allocation `new internal::TAsyncResultProvider<Message>(...)` happens to return for a given request carries whatever byte was already sitting at that offset, and for the `GetSimTime` request captured in `/ws/logs/20260820_182659/` that byte read as non-zero, so the request was silently discarded, `SendRequest()` never called, before `nng_send()` ever ran.

§2.1 separately establishes, by direct reading of `Client.cpp` and `AsyncResultInternal.h`, that `Request()`'s synchronous `Wait()` has no independent timeout anywhere in its own implementation, and that its one apparent safety net, a 300-second socket receive timeout, was, before §4.4's fix, defeated by `ResponseReceivingThreadProc()` treating that timeout as a reason to retry rather than a reason to give up. This remains a real, separate latent bug, a designed 300-second timeout the surrounding code never acted on is dead code regardless of what triggers a lost reply, but §3.5 shows it is not what makes these particular captures hang, the `GetSimTime` request in every capture in this document never reaches `nng_send()`, so it never reaches `nng_recv()`'s `NNG_ETIMEDOUT` branch either, timed out or not. What actually holds `Wait()` open forever is `RequestSendingThreadProc()`'s already-canceled branch (`Client.cpp:780-785`), which, on finding `FIsCanceled()` true, only logs and releases the entry, it never calls `SetDone()`, and `Wait()`'s `cv_done_.wait(ul)` loop (`AsyncResultInternal.h:53-58`) can only ever be woken by `SetDone()`.

### 4.2 Is the missing timeout deliberate?

`git blame -L 826,840 -- client/cpp/ProjectAirsimClientLib/src/Client.cpp`, and the same for the socket-option block at lines 270 to 282, both attribute every line of the retry loop and the timeout constants to a single commit, `eb9c12a0`, authored by `jonyMarino` on 2024-03-11, whose message is simply `"Initial commit"`. `git log --diff-filter=A -- client/cpp/AirSimClientDLL/src/Client.cpp` confirms this is not merely the first commit to touch the file, it is the commit that introduced the file, and the file's later rename from `AirSimClientDLL` to `ProjectAirsimClientLib` (commits `cf4a64b` and `fa404d0`, both titled `"Client cpp with all features"`) carried the content across unchanged, which is how `git blame` was able to trace lines written in 2024 through a 2025-era rename without losing attribution.

`git log --oneline --all -- client/cpp/ProjectAirsimClientLib/src/Client.cpp` shows only these two commits touching the file at its current path, and neither is a substantive edit to this region, they are the rename commits themselves.

This means there is no git history internal to this fork, `github.com/iamaisim/ProjectAirSim`, that documents a rationale for the retry-forever design, because no commit in this fork's visible history ever revisited it. The code arrived exactly as it stands today, in the very first commit of the fork, which is strong circumstantial evidence that this behaviour was inherited wholesale from whatever upstream Microsoft AirSim or Project AirSim codebase this fork was originally vendored from, rather than being a decision made, or even reconsidered, by any contributor to this repository. No `git diff` between two states of this logic exists to compare, because the logic has never changed.

The honest answer to the question is therefore that this cannot be shown to be a deliberate design choice validated by anyone working in this codebase, since nobody in this codebase's history has ever touched it, and the balance of evidence, an unbounded retry loop guarding a synchronous API with no way for a caller to recover, sitting on top of an explicitly disabled protocol-level resend option, is consistent with an oversight rather than an intentional liveness trade-off.

### 4.3 Trigger confirmed, uninitialized `fis_canceled_`

§2.2's unsynchronised-`methods_registry_` race and the three non-registry `RunJob()` candidates remain genuine, confirmed latent defects in `core_sim`, but §3.5's `/ws/logs/20260820_182037/` capture already ruled all four out as the trigger for these stalls, no `GetSimTime` request ever reached `RunJob()` for the server to mishandle in the first place, and §3.5's `/ws/logs/20260820_182659/` capture identifies where it was actually lost. `RequestAsync()` (`Client.cpp:597-621`) heap-allocates a fresh `internal::TAsyncResultProvider<Message>` for every request, whose base class, `TAsyncResultProviderBase`, declares `bool fis_canceled_` (`AsyncResultInternal.h:63`) but never initializes it, not in its own constructor (`:35-36`, which initializes `cv_done_`, `fis_done_(false)`, `mutex_`, and `status_(Status::InProgress)`, skipping `fis_canceled_`), and not in `TAsyncResultProvider<Message>`'s constructor either (`:110-112`, which only sets `fn_response_callback`). Reading an uninitialized `bool` is undefined behaviour, in practice it reads as whatever byte the heap allocator's last occupant of that memory left behind. `CancelRequest` and `/Sim/LoadScene`, allocated early in the session, happened to read `false`. The `GetSimTime` request allocated five seconds later, after considerably more heap churn from topic-list parsing and bridging setup, happened to read non-zero, so `RequestSendingThreadProc()`'s `FIsCanceled()` check (`:761`) was true from the moment the object was constructed, before it was ever queued, let alone canceled by anyone. The mechanism is intermittent by nature, since it depends on incidental heap contents rather than any deterministic input, which is consistent with this document's original baseline capture in §3.1 needing to isolate the failure at all rather than it being immediately obvious from a single run.

### 4.4 Solution

Two independent defects are now identified. The `NNG_ETIMEDOUT` retry-forever behaviour analysed in §4.1 and §4.2 is real dead code, but is not what causes the stalls captured in this document, since the request never reaches `nng_send()` for that branch to ever run. The actual trigger is the uninitialized `fis_canceled_` member confirmed in §4.3, which causes `RequestSendingThreadProc()`'s already-canceled branch (`Client.cpp:780-785`) to discard a request, silently, before it is ever sent, without calling `SetDone()`, which is what leaves the caller's `Wait()` blocked forever with no path to ever return, not a timeout, not an error, nothing.

The first fix, `ResponseReceivingThreadProc()`'s `NNG_ETIMEDOUT` branch (`Client.cpp:832-852`) now calling `pasyncresultprovider_message->SetDone(Status::TimedOut)` instead of `continue`, has been implemented, and remains independently justified, a genuinely lost reply after a request was actually sent should still surface as a bounded failure rather than an unbounded hang, but it does not fix any of the stalls reproduced in §3.5, since none of them ever reach the code path it changes. `Status::TimedOut` already existed in the enum (`Status.h:23`, `Status.cpp:52`), and the superseded `continue`-based branch is left commented out in place immediately above the replacement, per this workspace's code-change discipline.

The fix that actually addresses the confirmed trigger has now been implemented. `TAsyncResultProviderBase`'s constructor member-initializer list (`AsyncResultInternal.h:36-41`) now initializes `fis_canceled_(false)` alongside the members it already initialized, in declaration order, `cv_done_`, `fis_canceled_`, `fis_done_`, `mutex_`, `status_`, to match the class's field order (`:67-72`) and avoid a `-Wreorder` warning. This removes the undefined behaviour at its source and guarantees every newly constructed result provider starts uncanceled, matching every caller's implicit assumption already.

A second, independent hardening has also been implemented alongside it. `RequestSendingThreadProc()`'s already-canceled branch (`Client.cpp:768-772`) did not call `SetDone()` even in the case where `Cancel()` was called legitimately by a caller, so a real, intentional cancellation issued before a request is dequeued would have hung the caller's `Wait()` exactly the same way the uninitialized `fis_canceled_` did. That branch now calls `pasyncresultprovider_message->SetDone(Status::Canceled)` before falling through to `Release()`. Both changes are minimal and backwards-compatible, no caller's success path changes, and every existing caller of `Request()` already handles a non-`OK` `Status` return, `Status::Canceled` already existed in the enum and was already the status `CancelAllRequests()` used for the same purpose elsewhere.

Compilation could not be verified inside this container, for the same reason noted throughout §3 and §4, `Client.cpp` and `AsyncResultInternal.h` depend on headers from the vendored NNG and Unreal build trees not present outside the full ProjectAirSim build tree. Validation needs a live rebuild-and-run session with these changes applied, confirming `/clock` now publishes continuously from the first tick rather than stalling on the first `GetSimTime` request, that session has not yet been performed and should be the next entry appended to §3.

With the root cause confirmed and both fixes in place, the diagnostic logging added across §3.2 to §3.6 to trace this stall, the throttled `RequestSimTime`/`PublishClock` trace lines and the per-service `request received`/`request completed` wrapper logging in `projectairsim_ros2_cpp_node.cpp`, and the `Client: sending request_id`/`ResponseReceivingThreadProc`/`RequestSendingThreadProc` trace lines, the `RunJob`/`job_index`/`RegisterMethod`/`UnregisterAllMethods` logging in `service_manager.cpp`, and the phase-by-phase logging in `SimServer::SimReloadSceneWithJSON()`, has been removed from all four files. `core_sim/src/service_manager.cpp` and `simserver/src/simserver.cpp` are reverted to their pre-investigation state exactly, `git diff` against `HEAD` shows no changes in either. `Client.cpp` retains only the two behavioural fixes described above, no logging. `projectairsim_ros2_cpp_node.cpp` retains `StartClockTimerIfReady()`'s per-branch `RCLCPP_WARN`/`RCLCPP_INFO` guard logging and `RequestSimTime()`'s `RCLCPP_WARN_THROTTLE` failure logging, both of which report genuine, actionable conditions rather than tracing a healthy path, and are kept as ordinary operational logging rather than investigation instrumentation. The §3 sections describing what this instrumentation was and what it found in each capture remain as the historical record of the investigation, per this repository's `context/` convention of an incremental, non-destructive log, even though the logging itself no longer exists in the tree.

## 5. Conclusion

`/clock` never published because the very first `GetSimTime` request `projectairsim_ros2_cpp_node`'s clock timer ever issued was silently discarded by the client library before it was ever sent to the server. `RequestSendingThreadProc()` found `TAsyncResultProviderBase::fis_canceled_` already `true` on a freshly constructed request object, because that member was never initialized anywhere in the class hierarchy (`AsyncResultInternal.h:34-136` before this session's fix), so it read whatever byte was left in the heap memory `new` returned, and for this request that byte happened to be non-zero. The already-canceled branch that found it this way never called `SetDone()`, so the caller's blocking `Wait()` inside `RequestSimTime()` had no path back, ever, which froze the node's single-threaded `rclcpp` executor and, with it, every timer and service on the node, `/clock` included, indefinitely.

Nine successive log-capture sessions, recorded in `context/artefacts/project-airsim-clock-publication-bug/` and `/ws/logs/` and traced in §3, narrowed this from an initial, broad hypothesis about the ROS 2 executor and service dispatch, down to one call site, `client_->Request()` inside `RequestSimTime()`, then across the whole client-to-server wire once instrumentation reached both sides of it, to the exact line, `RequestSendingThreadProc()`'s already-canceled check, and finally to the exact root cause, the uninitialized member behind that check. A second, real but independent defect, `ResponseReceivingThreadProc()` previously retrying an `NNG_ETIMEDOUT` forever instead of failing the request, was found and fixed along the way, and remains worth keeping, but does not explain any stall reproduced in this document, since none of them ever reach that code.

Both fixes identified in §4.4 are now implemented, `fis_canceled_(false)` in `TAsyncResultProviderBase`'s constructor (`AsyncResultInternal.h:36-41`), and `SetDone(Status::Canceled)` in `RequestSendingThreadProc()`'s already-canceled branch (`Client.cpp:780-788`). What remains is a validation session confirming `/clock` now publishes continuously once these changes are built into a running stack.
