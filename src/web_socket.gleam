// import web_socket/frame
import gleam/option.{Option}

pub type Frame {
  Text(String)
  Binary(BitString)
  Ping(BitString)
  Pong(BitString)
  Close(code: Option(Int), reason: Option(String))
}
