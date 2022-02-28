import gleam/option.{Option, Some, None}
import gleam/bit_builder
import gleam/bit_string

pub type FrameData {
  Text(String)
  Binary(BitString)
  Continuation(BitString)
  Ping(BitString)
  Pong(BitString)
  Close(code: Option(Int), reason: Option(String))
}

pub type Frame {
  Frame(reserved: BitString, mask: Option(BitString), data: FrameData, fin: Bool)
}

fn encode_frame(frame: Frame) -> bit_builder.BitBuilder {
  let fin =
    case frame.fin {
      True -> <<1:size(1)>>
      False -> <<0:size(1)>>
    }

  let opcode =
    case frame.data {
      Continuation(_) -> <<0x0:size(1)>>
      Text(_) -> <<0x1:size(1)>>
      Binary(_) -> <<0x2:size(1)>>
      // 0x3-7 reserved for future non-control frames
      Close(..) -> <<0x8:size(1)>>
      Pong(_) -> <<0x9:size(1)>>
      Pong(_) -> <<0xA:size(1)>>
    }

  let is_masked_bit =
    case frame.mask {
      Some(_) -> <<1:size(1)>>
      None -> <<0:size(1)>>
    }

  bit_builder.new()
  |> bit_builder.append(fin)
  |> bit_builder.append(frame.reserved)
  |> bit_builder.append(opcode)
  |> bit_builder.append(is_masked_bit)
  |> bit_builder.append(option.unwrap(frame.mask, <<>>))
  |> bit_builder.append(mask_data(frame))
}

fn mask_data(frame: Frame) -> BitString {
  let data =
    case frame.data {
      Text(string) -> bit_string.from_string(string)
      Binary(bit_string) -> bit_string
      Continuation(bit_string) -> bit_string
      Ping(bit_string) -> bit_string
      Pong(bit_string) -> bit_string
      Close(code: None, reason: None) -> <<>>
      Close(code: code, reason: reason) ->
        // This should need to be unsigned but that's only allowed in patterns.
        // This might be ok as-is?
        //
        //     iex(1)> <<1000::unsigned-integer-size(8)-unit(2)>>
        //     <<3, 232>>
        //     iex(2)> <<1000::integer-size(8)-unit(2)>>
        //     <<3, 232>>
        //
        <<option.unwrap(code, 1000):int-size(8)-unit(2), option.unwrap(reason, ""):utf8>>
    }

  case frame.mask {
    Some(mask) -> apply_mask(data, mask, <<>>)
    None -> data
  }
}

// Mask the payload by bytewise XOR-ing the payload bytes against the mask
// bytes (where the mask bytes repeat).
//
// This is an "involution" function: applying the mask will mask
// the data and applying the mask again will unmask it.
fn apply_mask(data: BitString, mask: BitString, acc: BitString) -> BitString {
  // The only part that changes in each case is the number of bytes matched:
  // 4, 3, 2, 1, then 0 remaining data bytes. The mask is 4 bytes long, so we try
  // to match as many bytes of the data as possible to make the masking function
  // faster. The `unit(4)` branch is used for most of `data` but the trailing 0-3
  // bytes may fall into the other branches depending on the byte-size of `data`.
  case data, mask {
    <<part_key:int-size(8)-unit(4), rest:bit_string>>, <<
      mask_key:int-size(8)-unit(4),
      _:bit_string,
    >> ->
      apply_mask(
        rest,
        mask,
        <<acc:bit_string, bxor(mask_key, part_key):int-size(8)-unit(4)>>,
      )

    <<part_key:int-size(8)-unit(3), rest:bit_string>>, <<
      mask_key:int-size(8)-unit(3),
      _:bit_string,
    >> ->
      apply_mask(
        rest,
        mask,
        <<acc:bit_string, bxor(mask_key, part_key):int-size(8)-unit(3)>>,
      )

    <<part_key:int-size(8)-unit(2), rest:bit_string>>, <<
      mask_key:int-size(8)-unit(2),
      _:bit_string,
    >> ->
      apply_mask(
        rest,
        mask,
        <<acc:bit_string, bxor(mask_key, part_key):int-size(8)-unit(2)>>,
      )

    <<part_key:int-size(8)-unit(1), rest:bit_string>>, <<
      mask_key:int-size(8)-unit(1),
      _:bit_string,
    >> ->
      apply_mask(
        rest,
        mask,
        <<acc:bit_string, bxor(mask_key, part_key):int-size(8)-unit(1)>>,
      )

    <<>>, _mask -> acc
  }
}

fn new_mask() -> BitString {
  random_bytes(4)
}

// TODO: wrap in if-erlang
external fn bxor(Int, Int) -> Int = "erlang" "bxor"
external fn random_bytes(Int) -> BitString = "crypto" "strong_rand_bytes"
