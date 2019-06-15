open Tools
open Location
open Ident

module A = Ast
module M = Model
module W = Model_wse

let vtyp_to_type = function
  | A.VTbool       -> W.Tbool
  | A.VTint        -> W.Tint
  | A.VTuint       -> W.Tuint
  | A.VTrational   -> W.Trational
  | A.VTdate       -> W.Tdate
  | A.VTduration   -> W.Tduration
  | A.VTstring     -> W.Tstring
  | A.VTaddress    -> W.Taddress
  | A.VTrole       -> W.Trole
  | A.VTcurrency c -> W.Tcurrency c
  | A.VTkey        -> W.Tkey

let rec to_type = function
  | M.FBasic v              -> vtyp_to_type v
  | M.FAssetKeys (v, a)     -> W.Tcontainer (vtyp_to_type v)
  | M.FAssetRecord (v, a)   -> W.Tmap (vtyp_to_type v, Trecord (unloc a))
  | M.FRecordCollection a   -> W.Tcontainer (Trecord (unloc a))
  | M.FRecord a             -> W.Trecord (unloc a)
  | M.FEnum a               -> W.Tenum (unloc a)
  | M.FContainer (_, t)     -> W.Tcontainer (to_type t)

let to_expr (e : A.pterm) : W.expr =
  match e.node with
  | A.Plit {node = BVint v; }     -> W.Elitint v
  | A.Plit {node = BVaddress v; } -> W.Elitraw v
  | _ -> assert false

let rec ptyp_to_type = function
  | A.Tasset a          -> W.Trecord (unloc a)
  | A.Tenum e           -> W.Tenum (unloc e)
  | A.Tcontract c       -> W.Tcontract (unloc c)
  | A.Tbuiltin v        -> vtyp_to_type v
  | A.Tcontainer (t, _) -> W.Tcontainer (ptyp_to_type t)
  | A.Ttuple l          -> W.Ttuple (List.map ptyp_to_type l)

let get_default_expr_from_type = function
  | M.FBasic VTbool       -> W.Elitbool false
  | M.FBasic VTint        -> W.Elitint Big_int.zero_big_int
  | M.FBasic VTuint       -> W.Elitint Big_int.zero_big_int
  | M.FBasic VTrational   -> W.Elitint Big_int.zero_big_int
  | M.FBasic VTdate       -> W.Elitint Big_int.zero_big_int
  | M.FBasic VTduration   -> W.Elitint Big_int.zero_big_int
  | M.FBasic VTstring     -> W.Elitstring ""
  | M.FBasic VTaddress    -> assert false
  | M.FBasic VTrole       -> assert false
  | M.FBasic VTcurrency _ -> W.Elitraw "0tz"
  | M.FBasic VTkey        -> W.Elitint Big_int.zero_big_int
  | M.FAssetKeys (k, a)   -> W.Earray []
  | M.FAssetRecord (k, a) -> W.Elitmap (vtyp_to_type k, Trecord (unloc a))
  | M.FRecordCollection a -> assert false
  | M.FRecord _           -> assert false
  | M.FEnum _             -> assert false
  | M.FContainer (c, i)   -> assert false

type sig_ = W.kind_function * (ident * W.type_) list * W.type_ * W.expr

exception Anomaly of string

type error_desc =
  | UnsupportedContainer of string
  | UnsupportedType of string
  | RecordNotFound
[@@deriving show {with_path = false}]

let emit_error (desc : error_desc) =
  let str = Format.asprintf "%a@." pp_error_desc desc in
  raise (Anomaly str)

module Utils : sig
  val get_asset      : M.model -> A.lident              -> sig_
  val add_asset      : M.model -> A.lident              -> sig_
  val contains_asset : M.model -> A.lident              -> sig_
  val add_container  : M.model -> (A.lident * A.lident) -> sig_
end = struct
  open Model_wse

  let failwith str = Ecall (Evar "failwith", [Elitstring str])

  let get_asset model asset =
    let asset_name = unloc asset in
    let _, key_type = M.Utils.get_record_key model asset in
    let args = [("s", Tstorage); ("key", vtyp_to_type key_type) ] in
    let ret  = Trecord asset_name in
    let body =
      Ematchwith (Ecall (Edot (Evar "Map", "find"),
                         [
                           Evar "key";
                           Edot (Evar "s",
                                 asset_name ^ "_assets")
                         ]),
                  [
                    (Pexpr (Ecall (Evar "Some", [Evar "v"])), Evar "v");
                    (Pwild,  failwith "not_found") ])
    in
    Function, args, ret, body

  let add_asset model asset =
    let asset_name = unloc asset in
    let key_id, _ = M.Utils.get_record_key model asset |> fun (x, y) -> unloc x , y in
    let new_asset = "new_asset" in
    let storage_id = "s" in
    let col_asset_id = asset_name ^ "_assets" in
    let col_keys_id = asset_name ^ "_keys" in
    let args = [(storage_id, Tstorage); (new_asset, Trecord asset_name) ] in
    let ret  = Tstorage in
    let s_col_asset_id = Edot (Evar storage_id, col_asset_id) in
    let s_col_keys_id = Edot (Evar storage_id, col_keys_id) in
    let new_asset_key = Edot (Evar new_asset, key_id) in
    let body =
      Eletin (
        [
          [storage_id, Tstorage], Eassign (s_col_asset_id, Ecall (Edot (Evar "Map","add"), [new_asset_key; Evar new_asset; s_col_asset_id]));
          [storage_id, Tstorage], Eassign (s_col_keys_id, Eaddlist (new_asset_key, s_col_keys_id))
        ], Evar storage_id)
    in
    Function, args, ret, body

  let contains_asset model asset =
    let asset_name = unloc asset in
    let _, key_type = M.Utils.get_record_key model asset in
    let args = [("s", Tstorage); ("key", vtyp_to_type key_type) ] in
    let ret  = Tbool in
    let body =
      Ematchwith (Ecall (Edot (Evar "Map", "find"),
                         [
                           Evar "key";
                           Edot (Evar "s",
                                 asset_name ^ "_assets")
                         ]),
                  [
                    (Pexpr (Ecall (Evar "Some", [Evar "_"])), Elitbool true);
                    (Pwild,  Elitbool false)])
    in
    Function, args, ret, body

  let add_container_collection model (asset, field) t = assert false

  let add_container_partition model ((asset, field) : A.lident * M.record_item) t =
    let field_ptype = ptyp_to_type t in
    let asset2_name = unloc asset in
    let asset2_key_id, _ = M.Utils.get_record_key model asset in
    let asset_name = match field_ptype with
      | Trecord v -> v
      | _ -> emit_error RecordNotFound in
    let storage_id = "s" in
    let new_asset_id = "new_asset" in
    let args = [(storage_id, Tstorage); ("a", Trecord asset2_name); (new_asset_id, field_ptype)] in
    let ret  = Tstorage in
    let key_id, _ = M.Utils.get_record_key model (dumloc asset_name) |> fun (x, y) -> unloc x , y in
    let col_asset2_id   = asset2_name ^ "_assets" in
    let col_asset_id    = asset_name  ^ "_assets" in
    let col_keys_id     = asset_name  ^ "_keys" in
    let s_col_asset2_id = Edot (Evar storage_id,   col_asset2_id) in
    let s_col_asset_id  = Edot (Evar storage_id,   col_asset_id) in
    let s_col_keys_id   = Edot (Evar storage_id,   col_keys_id) in
    let new_asset_key   = Edot (Evar new_asset_id, key_id) in
    let aaa = Edot (Evar "v", unloc field.name) in
    let body =
      Eletin (
        [
          [storage_id, Tstorage], Eassign (s_col_asset_id, Ecall (Edot (Evar "Map","add"), [new_asset_key; Evar new_asset_id; s_col_asset_id]));
          [storage_id, Tstorage], Eassign (s_col_keys_id, Eaddlist (new_asset_key, s_col_keys_id));
          [storage_id, Tstorage], Eassign (s_col_asset2_id, Ematchwith (Ecall (Edot (Evar "Map", "find"),
                                                                               [
                                                                                 Edot (Evar "a", unloc asset2_key_id);
                                                                                 Edot (Evar storage_id, col_asset2_id)
                                                                               ]),
                                                                        [
                                                                          (Pexpr (Ecall (Evar "Some", [Evar "v"])),

                                                                           Eletin ([["new_casset", Trecord asset2_name], Eassign (aaa, Eaddlist (Evar new_asset_id, aaa))],
                                                                                   Ecall (Edot (Evar "Map","update"), [Edot (Evar "a", unloc asset2_key_id); Ecall (Evar "(Some", [Evar "new_casset)"]); s_col_asset2_id]))
                                                                          );
                                                                          (Pwild, failwith "not found")]))
        ], Evar storage_id)
    in
    Function, args, ret, body


  let add_container model (asset, field) =
    let field = M.Utils.get_record_field model (asset, field) in
    match field.type_ with
    | Tcontainer (t, A.Collection) -> add_container_collection model (asset, field) t
    | Tcontainer (t, A.Partition)  -> add_container_partition  model (asset, field) t
    | Tcontainer (t, c) -> emit_error (UnsupportedContainer (Format.asprintf "%a@." A.pp_container c))
    | t -> emit_error (UnsupportedType (Format.asprintf "%a@." A.pp_ptyp t))

end

let mk_function_struct model (f : M.function__) =
  let name : ident = M.function_name_from_function_node f.node in
  let kind, args, ret, body =
    match f.node with
    | M.Entry _ ->
      let args = [("params", W.Tunit); ("s", W.Tstorage) ] in
      let ret  = W.Ttuple [W.Toperations; W.Tstorage] in
      let body = W.Etuple [W.Earray []; W.Evar "s"] in
      W.Entry, args, ret, body

    | M.Get asset                   -> Utils.get_asset model asset
    | M.AddAsset asset              -> Utils.add_asset model asset
    | M.ContainsAsset asset         -> Utils.contains_asset model asset
    | M.AddContainer (asset, field) -> Utils.add_container model (asset, field)

    | _ ->
      let args = ["", W.Tunit] in
      let ret  = W.Tunit in
      let body = W.Etuple [] in
      W.Function, args, ret, body
  in

  W.mk_function name kind ret body ~args:args

let remove_se (model : M.model) : W.model =
  let name = model.name in
  let enums = List.fold_left (fun accu x ->
      match x with
      | M.TNenum e ->
        let name = unloc e.name in
        let values : ident list = List.map (fun (x : M.enum_item) -> unloc x.name) e.values in
        let enum = W.mk_enum name ~values:values in
        accu @ [enum]
      | _ -> accu) [] model.decls in
  let records = List.fold_left (fun accu x ->
      match x with
      | M.TNrecord r ->
        let values : (ident * W.type_ * W.expr) list =
          List.map (fun (x : M.record_item) -> (unloc x.name, ptyp_to_type x.type_, W.Elitbool false)) r.values
        in
        accu @
        [W.mk_record (unloc r.name) ~values:values]
      | M.TNstorage s ->
        let values : (ident * W.type_ * W.expr) list =
          List.fold_left (fun accu (x : M.storage_item) ->
              accu @ List.map (fun (i : M.item_field) : (ident * W.type_ * W.expr) ->
                  (unloc i.name, to_type i.typ, (
                      match i.default with
                      | Some v -> to_expr v
                      | None -> get_default_expr_from_type i.typ
                    ))) x.fields
            ) [] s
        in
        accu @
        [W.mk_record "storage" ~values:values]
      | _ -> accu
    ) [] model.decls in
  let funs = List.fold_left (fun accu x ->
      match x with
      | M.TNfunction f ->
        let func = mk_function_struct model f in
        accu @ [func]
      | _ -> accu) [] model.decls in
  W.mk_model (unloc name) ~enums:enums ~records:records ~funs:funs
