open Location
open Model
open Tools

let field_bool_id = "_isValue"

let replace_add_update_by_update (model : model) : model =
  let is_checked (an, l : string * (lident * assignment_operator * mterm) list) =
    let is_default_solidity_value (mt : mterm) =
      match mt.node, mt.type_ with
      | Mint v, Tbuiltin Bint when Big_int.eq_big_int Big_int.zero_big_int v -> true
      | Mbool false, Tbuiltin Bbool -> true
      | _ -> false
    in
    let asset : asset = Utils.get_asset model an in
    let lref : (Ident.ident * (assignment_operator * mterm)) list = List.map (fun (x, y, z) -> (unloc x, (y, z))) l in
    try
      List.iter (
        fun (f : asset_item) ->
          let f_name = (unloc f.name) in
          if not (String.equal asset.key f_name)
          then
            begin
              match List.assoc_opt f_name lref with
              | Some (ValueAssign, _) -> ()
              | _ ->
                begin
                  match f.default with
                  | Some v when is_default_solidity_value v -> ()
                  | _ -> raise Not_found
                end
            end
      ) asset.values;
      true
    with
    | Not_found -> false
  in
  let rec aux (ctx : ctx_model) (mt : mterm) : mterm =
    match mt.node with
    | Maddupdate (an, k, l) when is_checked (an, l)-> {mt with node = Mupdate (an, k, l)}
    | _ -> map_mterm (aux ctx) mt
  in
  map_mterm_model aux model

let replace_update_by_assignment (model : model) : model =
  let n_key = ref 0 in
  let get_fresh_id_key () =
    begin
      let res = "_k_" ^ string_of_int !n_key in
      n_key := !n_key + 1;
      res
    end
  in
  let n_asset = ref 0 in
  let get_fresh_id_asset () =
    begin
      let res = "_asset_" ^ string_of_int !n_asset in
      n_asset := !n_asset + 1;
      res
    end
  in
  let rec aux (ctx : ctx_model) (mt : mterm) : mterm =
    match mt.node with
    | Mupdate (an, k, l) ->
      begin
        (* let asset = Utils.get_asset model an in *)
        let is_asset_name (pterm : mterm) an : bool =
          match pterm with
          | {type_ = Tasset asset_name} -> String.equal an (unloc asset_name)
          | _ -> false
        in

        let _, t = Utils.get_asset_key model an in

        let type_asset = Tasset (dumloc an) in
        let type_container_asset = Tcontainer (type_asset, Collection) in

        let var_name = dumloc (get_fresh_id_asset ()) in
        let var_mterm : mterm = mk_mterm (Mvarlocal var_name) type_asset in

        (* let asset_mterm : mterm = mk_mterm (Mvarstorecol (dumloc (asset_name))) type_container_asset in *)

        let asset_aaa =
          match k.node with
          | Mdotasset (a, _) when is_asset_name a an -> Some a
          | _ -> None
        in

        let key_name = get_fresh_id_key () in
        let key_loced : lident = dumloc (key_name) in
        let key_mterm : mterm =
          match asset_aaa with
          | Some _ -> k
          | _ ->
            mk_mterm (Mvarlocal key_loced) type_container_asset
        in

        (* let set_mterm : mterm = mk_mterm (Mset (an, List.map (fun (id, _, _) -> unloc id) l, key_mterm, var_mterm)) Tunit in

           let lref : (Ident.ident * (assignment_operator * mterm)) list = List.map (fun (x, y, z) -> (unloc x, (y, z))) l in
           let lassetitems =
           List.fold_left (fun accu (x : asset_item) ->
              let v = List.assoc_opt (unloc x.name) lref in
              let type_ = x.type_ in
              let var = mk_mterm (Mdotasset (var_mterm, x.name)) type_ in
              match v with
              | Some y ->
                accu @ [
                  let value = snd y in
                  match y |> fst with
                  | ValueAssign -> value
                  | PlusAssign  -> mk_mterm (Mplus (var, value)) type_
                  | MinusAssign -> mk_mterm (Mminus (var, value)) type_
                  | MultAssign  -> mk_mterm (Mmult (var, value)) type_
                  | DivAssign   -> mk_mterm (Mdiv (var, value)) type_
                  | AndAssign   -> mk_mterm (Mand (var, value)) type_
                  | OrAssign    -> mk_mterm (Mor (var, value)) type_
                ]
              | _ -> accu @ [var]
            ) [] asset.values in
           let asset : mterm = mk_mterm (Masset lassetitems) type_asset in

           let letinasset : mterm = mk_mterm (Mletin ([var_name],
                                                   asset,
                                                   Some (type_asset),
                                                   set_mterm,
                                                   None
                                                  )) Tunit in *)

        let ll = List.map (
            fun (id, op, v) ->
              mk_mterm (Massignfield (op, Tunit, var_mterm, id, v)) Tunit
          ) l in
        let seq_node = Mseq ll in
        let seq = mk_mterm seq_node Tunit in


        let get_mterm : mterm =
          match asset_aaa with
          | Some a -> a
          | _ ->
            mk_mterm (Mget (an, key_mterm)) type_asset
        in

        let letinasset : mterm = mk_mterm (Mletin ([var_name],
                                                   get_mterm,
                                                   Some (type_asset),
                                                   seq,
                                                   None
                                                  ))
            Tunit in

        let res : mterm__node =
          match asset_aaa with
          | Some _ -> letinasset.node
          | _ ->
            Mletin ([key_loced],
                    k,
                    Some (Tbuiltin t),
                    letinasset,
                    None
                   ) in

        mk_mterm res Tunit
      end
    | _ -> map_mterm (aux ctx) mt
  in
  map_mterm_model aux model

let add_bool_asset (model : model) : model =
  let field_type = Tbuiltin Bbool in
  let field_value = mk_mterm (Mbool true) field_type in
  let rec aux (ctx : ctx_model) (mt : mterm) : mterm =
    match mt.node with
    | Masset l ->
      begin
        { mt with node = Masset (l @ [field_value]) }
      end
    | _ -> map_mterm (aux ctx) mt
  in
  { model with
    decls = List.map (fun d ->
        match d with
        | Dasset a -> Dasset {a with values = a.values @ [mk_asset_item (dumloc field_bool_id) field_type field_type]}
        | _ -> d
      ) model.decls
  }
  |> map_mterm_model aux

let make_asset_var (model : model) : model =
  let n = ref 0 in
  let get_fresh_id () =
    begin
      let res = "_asset_var_" ^ string_of_int !n in
      n := !n + 1;
      res
    end
  in
  let is_masset (x : mterm) = match x.node with | Masset _ -> true | _ -> false in
  let rec aux (ctx : ctx_model) (mt : mterm) : mterm =
    match mt.node with
    | Maddasset (an, v) when is_masset v ->
      begin
        let asset_type = Tasset (dumloc an) in
        let var_id = get_fresh_id () in
        let var_lident = dumloc var_id in
        let var = mk_mterm (Mvarlocal var_lident) asset_type in
        let body = mk_mterm (Maddasset (an, var)) Tunit in
        let letin = Mletin ([var_lident], v, Some asset_type, body, None) in
        mk_mterm letin Tunit
      end
    | _ -> map_mterm (aux ctx) mt
  in
  map_mterm_model aux model