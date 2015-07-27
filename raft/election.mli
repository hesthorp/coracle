open Common
open Rpcs

type eventsig = State.t -> Global.t -> State.t option * rpc Io.output list * Global.t

val receive_vote_request: id -> RequestVoteArg.t -> eventsig
val receive_vote_reply: id -> RequestVoteRes.t -> eventsig
val start_election: eventsig
val restart_election: eventsig
val start_follower: eventsig