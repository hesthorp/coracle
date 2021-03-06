open Common
open Io
open Yojson.Safe
open States

module Simulate = 
  functor (C: Protocol.CONSENSUS) -> struct

  let trace_buffer = ref []

  let buffer_many flush jsons = 
    match flush with 
    | true -> pretty_to_channel ~std:true stdout (`List jsons)
    | false -> trace_buffer := jsons @ !trace_buffer

  let buffer flush json = buffer_many flush [json]
  

  let json_to_stdout json = 
    to_channel ~std:true stdout json

  let flush_buffer general client protocol = 
    json_to_stdout (
      `Assoc [
        ("trace", `List !trace_buffer);
        ("results", `Assoc [
          ("network", general);
          ("client", client);
          ("protocol specific", protocol);
        ]);
      ])

  let input_event_to_json time id event = 
    `Assoc [
      ("time", `Int time);
      ("id", `Int id);
      ("event", input_to_json C.msg_to_json event); 
    ]

  let output_event_to_json time id event = 
    `Assoc [
      ("time", `Int time);
      ("id", `Int id);
      ("event", output_to_json C.msg_to_json event); 
    ]

  let output_events_to_json time id events = 
    List.map (output_event_to_json time id) events


  let state_to_json time id state = 
    `Assoc [
     ("time", `Int time);
     ("id", `Int id);
     ("event", C.Server.state_to_json state); ]

  let client_state_to_json time id state = 
    `Assoc [
     ("time", `Int time);
     ("id", `Int id);
     ("event", C.Client.state_to_json state); ]

  let rec run ss mss es trace output_file global term debug =
    let rec eval ss mss es g =
      let open Events in 
      match Events.next es with
      | Next ((t,n,e),new_es) -> 
        let g = C.set_state t n g in
        if trace then buffer debug (input_event_to_json t n e) else (); (
        match e with
        | LocalArrival _ | LocalTimeout -> (
          (* i am a local event *)
          match States.get n mss with
          | Server ms -> 
             (* i am a server side application *)
             let (new_ms,new_e) = App.StateMachine.eval t e ms in 
             eval ss (States.set_server n new_ms mss) (Events.add n t new_e new_es) g
          | Client ms -> 
             (* i am a client side application *)
             let (new_ms,new_e) = App.Client.eval t e ms in 
             eval ss (States.set_client n new_ms mss) (Events.add n t new_e new_es) g
          )
        | _ -> (
          (* i am not a local event *)
          match States.get n ss with
          | Server s -> 
            (* i am a server *)
            let (new_s,new_e,new_g) = C.Server.eval e s g in 
            if trace then buffer_many debug (output_events_to_json t n new_e) else ();
            (
            match trace, new_s with
            | true, Some state -> buffer debug (state_to_json t n state)
            | _ -> ()
            );
            eval (States.set_server n new_s ss) mss (Events.add n t new_e new_es) new_g
          | Client s -> 
            (* i am a client *)
            let (new_s,new_e,new_g) = C.Client.eval e s g in 
            if trace then buffer_many debug (output_events_to_json t n new_e) else ();
            (
            match trace, new_s with
            | true, Some state -> buffer debug (client_state_to_json t n state)
            | _ -> ()
            );
            eval (States.set_client n new_s ss) mss (Events.add n t new_e new_es) new_g
            ))
      | NoNext new_es -> 
        flush_buffer (Events.json_of_stats new_es) (App.json_of_stats term (States.clients mss) (States.servers mss)) (C.global_to_json g) in 
    eval ss mss es global

  let start config_file trace output_file no_sanity debug = 
    let json = Json_handler.json_from_file config_file in
    let para = Json_handler.parameters_from_json json in
    let protocol_json = Json_handler.proto_json_from_json json in
    let servers = Network.count_servers para.network in
    let clients = Network.count_clients para.network in
    if no_sanity then () else Parameters.check_sanity para;
    Numbergen.init para.seed;
    let config = C.parse_config servers clients protocol_json in
    let ss = States.init 
      ~server_init:(fun n -> C.Server.init n config) 
      ~client_init:(fun n -> C.Client.init n config) servers clients in
    let mss = States.init 
      ~server_init:(App.StateMachine.init para)
      ~client_init:(App.Client.init para) servers clients in
    run ss mss (Events.init para) trace output_file C.reset_global para.term debug

end