open Location
open Model
open Printer_tools

module T = Michelson

let prelude fmt _ =
  Format.fprintf fmt
    "/* Bindings typescript generated by archetype version: %s */

import { MichelsonType } from '@taquito/michel-codec';
import { Schema } from '@taquito/michelson-encoder';
import { registerEvent, ShaftEvent, ShaftEventProcessor, hex_to_data } from '@completium/event-indexer';
" Options.version

type type_kind =
  | Type
  | Init of string

let rec to_type (tk : type_kind) fmt (t : type_) =
  let pp = Format.fprintf fmt in
  let todo        _ = pp "TODO" in
  let unsupported _ = pp "Unsupported" in
  let number      _ = pp "BigNumber" in
  let string      _ = pp "string" in
  let bytes       _ = pp "Bytes" in
  let date        _ = pp "Date" in
  let bool        _ = pp "bool" in
  let self = to_type tk fmt in
  let doit a b =
    match tk with
    | Type -> a ()
    | Init f -> b f
  in
  let id_f = (fun f -> Format.fprintf fmt "%s" f ) in
  match get_ntype t with
  | Tasset _                        -> todo()
  | Tenum _                         -> todo()
  | Tstate                          -> todo()
  | Tbuiltin Bunit                  -> todo()
  | Tbuiltin Bbool                  -> doit bool   todo
  | Tbuiltin Bint                   -> doit number todo
  | Tbuiltin Brational              -> todo()
  | Tbuiltin Bdate                  -> doit date   (fun f -> Format.fprintf fmt "new Date(parseInt(%s, 10) * 1000)" f )
  | Tbuiltin Bduration              -> doit number todo
  | Tbuiltin Btimestamp             -> doit date   todo
  | Tbuiltin Bstring                -> doit string id_f
  | Tbuiltin Baddress               -> doit string id_f
  | Tbuiltin Bcurrency              -> doit number todo
  | Tbuiltin Bsignature             -> doit string todo
  | Tbuiltin Bkey                   -> doit string todo
  | Tbuiltin Bkeyhash               -> doit string todo
  | Tbuiltin Bbytes                 -> doit bytes  todo
  | Tbuiltin Bnat                   -> doit number todo
  | Tbuiltin Bchainid               -> doit string todo
  | Tbuiltin Bbls12_381_fr          -> doit bytes  todo
  | Tbuiltin Bbls12_381_g1          -> doit bytes  todo
  | Tbuiltin Bbls12_381_g2          -> doit bytes  todo
  | Tbuiltin Bnever                 -> unsupported()
  | Tbuiltin Bchest                 -> doit bytes  todo
  | Tbuiltin Bchest_key             -> doit bytes  todo
  | Tcontainer _                    -> unsupported()
  | Tlist _ty                       -> todo()
  | Toption ty                      -> self ty
  | Ttuple _tys                     -> todo()
  | Tset _ty                        -> todo()
  | Tmap (false, _kty, _vty)        -> todo()
  | Tmap (true, _kty, _vty)         -> unsupported()
  | Tor (_lty, _rty)                -> todo()
  | Trecord _id                     -> todo()
  | Tevent _id                      -> todo()
  | Tlambda (_ity, _rty)            -> todo()
  | Tunit                           -> todo()
  | Tstorage                        -> todo()
  | Toperation                      -> unsupported()
  | Tcontract _                     -> unsupported()
  | Tprog _                         -> unsupported()
  | Tvset _                         -> unsupported()
  | Ttrace _                        -> unsupported()
  | Tticket _                       -> unsupported()
  | Tsapling_state _                -> unsupported()
  | Tsapling_transaction _          -> todo()


type input_event = {
  r : record;
  ty : T.obj_micheline;
}

let mk_input_event r ty : input_event =
  { r; ty }

let pp_event fmt (ie : input_event) =
  let pp_interface fmt =
    let pp_field fmt (f : record_field) =
      Format.fprintf fmt "%a : %a" pp_id f.name (to_type Type) f.type_
    in
    Format.fprintf fmt "export interface %a extends ShaftEvent {@\n  @[%a@]@\n}"
      pp_id ie.r.name
      (pp_list ",@\n" pp_field) ie.r.fields
  in
  let pp_michelson_type fmt =
    Format.fprintf fmt "const michelsonType_%a: MichelsonType =@\n%a;" pp_id ie.r.name Printer_michelson.pp_obj_micheline ie.ty
  in
  let pp_make fmt =
    let pp_field fmt (f : record_field) =
      Format.fprintf fmt "%a : %a" pp_id f.name (to_type (Init ("data." ^ unloc f.name))) f.type_
    in
    Format.fprintf fmt "function make_%a(input: string): %a | undefined {
  const data = hex_to_data(michelsonType_%a, input)

  if (data._kind !== '%a') {
    return undefined;
  }
  return { @[%a@] }
}"
      pp_id ie.r.name
      pp_id ie.r.name
      pp_id ie.r.name
      pp_id ie.r.name
      (pp_list ",@\n" pp_field) ie.r.fields
  in
  let pp_register fmt =
    Format.fprintf fmt "export function register_%a(source : string, handler : ShaftEventProcessor<%a>) {
  registerEvent({ s: source, c: make_%a, p: handler })
}"
      pp_id ie.r.name
      pp_id ie.r.name
      pp_id ie.r.name
  in
  let pp_newline fmt = Format.fprintf fmt "@\n@\n" in

  Format.fprintf fmt "/* Event: %a */" pp_id ie.r.name;
  pp_newline fmt;
  pp_interface fmt;
  pp_newline fmt;
  pp_michelson_type fmt;
  pp_newline fmt;
  pp_make fmt;
  pp_newline fmt;
  pp_register fmt

let process(model : model) : string =
  let events = List.map (fun (r : record) ->
      let kt = mktype (Tbuiltin Bstring) ~annot:(dumloc "%_kind") in
      let ty = mktype (Tevent r.name) in
      mk_input_event r (Michelson.Utils.type_to_micheline (Gen_michelson.to_type model (ttuple [kt ; ty])))
    ) (Model.Utils.get_events model)
  in
  Format.asprintf "%a@\n%a@."
    prelude ()
    (pp_list "@\n@\n@\n" pp_event) events
