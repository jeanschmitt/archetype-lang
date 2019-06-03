(* -------------------------------------------------------------------- *)
open Ident
open Tools
open Location

module L  = Location
module PT = ParseTree
module M  = Model

(* -------------------------------------------------------------------- *)
module Type : sig
  val as_container : M.ptyp -> (M.ptyp * M.container) option
  val as_asset     : M.ptyp -> M.lident option
  val as_tuple     : M.ptyp -> (M.ptyp list) option

  val compatible : from_:M.ptyp -> to_:M.ptyp -> bool
end = struct
  let as_container = function M.Tcontainer (ty, c) -> Some (ty, c) | _ -> None
  let as_asset     = function M.Tasset     x       -> Some x       | _ -> None
  let as_tuple     = function M.Ttuple     ts      -> Some ts      | _ -> None

  let compatible ~(from_ : M.ptyp) ~(to_ : M.ptyp) =
    match from_, to_ with
    | _, _ when from_ = to_ ->
      true

    | M.Tbuiltin M.VTaddress, M.Tbuiltin M.VTrole ->
      true

    | _, _ ->
      false
end

(* -------------------------------------------------------------------- *)
type error_desc =
  | AssetExpected
  | CannotInferAnonRecord
  | CannotInferCollectionType
  | CollectionExpected
  | DivergentExpr
  | DuplicatedAssetName                of ident
  | DuplicatedCtorName                 of ident
  | DuplicatedFieldInAssetDecl         of ident
  | DuplicatedFieldInRecordLiteral     of ident
  | DuplicatedInitMarkForCtor
  | DuplicatedVarDecl                  of ident
  | EmptyStateDecl
  | ExpressionExpected
  | FormulaExpected
  | IncompatibleTypes                  of M.ptyp * M.ptyp
  | InvalidArcheTypeDecl
  | InvalidAssetExpression
  | InvalidCallByExpression
  | InvalidEffect
  | InvalidExpression
  | InvalidFieldsCountInRecordLiteral
  | InvalidLValue
  | InvalidFormula
  | InvalidInstruction
  | InvalidNumberOfArguments           of int * int
  | InvalidStateExpression
  | MissingFieldInRecordLiteral        of ident
  | MixedAnonInRecordLiteral
  | MixedFieldNamesInRecordLiteral     of ident list
  | MoreThanOneInitState               of ident list
  | MultipleInitialMarker
  | MultipleStateDeclaration
  | NameIsAlreadyBound                 of ident
  | NoSuchMethod                       of ident
  | NotARole                           of ident
  | OpInRecordLiteral
  | ReadOnlyGlobal                     of ident
  | SpecOperatorInExpr
  | UnknownAsset                       of ident
  | UnknownField                       of ident * ident
  | UnknownFieldName                   of ident
  | UnknownLocalOrVariable             of ident
  | UnknownProcedure                   of ident
  | UnknownState                       of ident
  | UnknownTypeName                    of ident
[@@deriving show {with_path = false}]

type error = L.t * error_desc

(* -------------------------------------------------------------------- *)
type effect  = unit
type argtype = [`Type of M.type_ | `Effect of ident]

type procsig = {
  psl_sig  : argtype list;
  psl_ret  : M.ptyp;
}

(* -------------------------------------------------------------------- *)
type assetdecl = {
  as_name   : M.lident;
  as_fields : (ident * M.ptyp) list;
}

(* -------------------------------------------------------------------- *)
type vardecl = {
  vr_name : M.lident;
  vr_type : M.ptyp;
  vr_kind : [`Constant | `Variable];
}

(* -------------------------------------------------------------------- *)
type actiondecl = {
  ad_name : M.lident;
}

(* -------------------------------------------------------------------- *)
type transitiondecl = {
  td_name : M.lident;
}

(* -------------------------------------------------------------------- *)
type statedecl = {
  sd_ctors : (M.lident * M.pterm list) list;
  sd_init  : ident;
}

(* -------------------------------------------------------------------- *)
type xexpr = [`Expr of M.pterm | `Asset of assetdecl]

let xexpr_as_expr  (e : xexpr) = match e with `Expr  e -> Some e | _ -> None
let xexpr_as_asset (e : xexpr) = match e with `Asset a -> Some a | _ -> None

let pterm_arg_as_pterm = function M.AExpr e -> Some e | _ -> None

(* -------------------------------------------------------------------- *)
let procsig_of_operator (_op : PT.operator) : procsig =
  assert false

(* -------------------------------------------------------------------- *)
let core_types = [
  ("string" , M.vtstring        );
  ("int"    , M.vtint           );
  ("uint"   , M.vtint           ); (* FIXME *)
  ("bool"   , M.vtbool          );
  ("role"   , M.vtrole          );
  ("address", M.vtaddress       );
  ("date"   , M.vtdate          );
  ("tez"    , M.vtcurrency M.Tez);
]

(* -------------------------------------------------------------------- *)
module Env : sig
  type t

  type entry = [
    | `State      of statedecl
    | `Type       of M.ptyp
    | `Local      of M.ptyp
    | `Global     of vardecl
    | `Proc       of procsig
    | `Asset      of assetdecl
    | `Action     of actiondecl
    | `Transition of transitiondecl
  ]

  type ecallback = error -> unit

  val create     : ecallback -> t
  val emit_error : t -> error -> unit
  val name_free  : t -> ident -> bool
  val lookup     : t -> ident -> entry option

  module Type : sig
    val lookup : t -> ident -> M.ptyp option
    val get    : t -> ident -> M.ptyp
    val exists : t -> ident -> bool
    val push   : t -> (ident * M.ptyp) -> t
  end

  module Local : sig
    val lookup : t -> ident -> (ident * M.ptyp) option
    val get    : t -> ident -> (ident * M.ptyp)
    val exists : t -> ident -> bool
    val push   : t -> ident * M.ptyp -> t
  end

  module Var : sig
    val lookup : t -> ident -> vardecl option
    val get    : t -> ident -> vardecl
    val exists : t -> ident -> bool
    val push   : t -> vardecl -> t
  end

  module Proc : sig
    val lookup : t -> ident -> procsig option
    val get    : t -> ident -> procsig
    val exists : t -> ident -> bool
  end

  module State : sig
    val byname : t -> ident -> ident option
    val push   : t -> statedecl -> t
  end

  module Asset : sig
    val lookup  : t -> ident -> assetdecl option
    val get     : t -> ident -> assetdecl
    val exists  : t -> ident -> bool
    val byfield : t -> ident -> (assetdecl * M.ptyp) option
    val push    : t -> assetdecl -> t
  end

  module Action : sig
    val lookup  : t -> ident -> actiondecl option
    val get     : t -> ident -> actiondecl
    val exists  : t -> ident -> bool
    val push    : t -> actiondecl -> t
  end

  module Transition : sig
    val lookup  : t -> ident -> transitiondecl option
    val get     : t -> ident -> transitiondecl
    val exists  : t -> ident -> bool
    val push    : t -> transitiondecl -> t
  end
end = struct
  type ecallback = error -> unit

  type entry = [
    | `State      of statedecl
    | `Type       of M.ptyp
    | `Local      of M.ptyp
    | `Global     of vardecl
    | `Proc       of procsig
    | `Asset      of assetdecl
    | `Action     of actiondecl
    | `Transition of transitiondecl
  ]

  type t = {
    env_error    : ecallback;
    env_bindings : entry Mid.t;
    env_fields   : ident Mid.t;
  }

  let create ecallback : t =
    { env_error    = ecallback;
      env_bindings = Mid.empty;
      env_fields   = Mid.empty; }

  let emit_error (env : t) (e : error) =
    env.env_error e

  let name_free (env : t) (x : ident) =
    not (Mid.mem x env.env_bindings)

  let lookup (env : t) (name : ident) : entry option =
    Mid.find_opt name env.env_bindings

  let lookup_gen (proj : entry -> 'a option) (env : t) (name : ident) : 'a option =
    Option.bind proj (lookup env name)

  let push (env : t) (name : ident) (entry : entry) =
    { env with env_bindings = Mid.add name entry env.env_bindings }

  module Type = struct
    let proj (entry : entry) =
      match entry with
      | `Type  x    -> Some x
      | `Asset decl -> Some (M.Tasset decl.as_name)
      | _           -> None

    let lookup (env : t) (name : ident) =
      lookup_gen proj env name

    let exists (env : t) (name : ident) =
      Option.is_some (lookup env name)

    let get (env : t) (name : ident) =
      Option.get (lookup env name)

    let push (env : t) ((name, ty) : ident * M.ptyp) =
      push env name (`Type ty)
  end

  module State = struct
    let byname (env : t) (name : ident) =
      match Mid.find_opt name env.env_bindings with
      | Some (`State _) -> Some name
      | _ -> None

    let push (env : t) (decl : statedecl) =
      List.fold_left (fun env ({ pldesc = name }, _) ->
          { env with env_bindings =
                       Mid.add name (`State decl) env.env_bindings })
        env decl.sd_ctors
  end

  module Local = struct
    let proj = function `Local x -> Some x | _ -> None

    let lookup (env : t) (name : ident) =
      Option.map (fun ty -> (name, ty)) (lookup_gen proj env name)

    let exists (env : t) (name : ident) =
      Option.is_some (lookup env name)

    let get (env : t) (name : ident) =
      Option.get (lookup env name)

    let push (env : t) ((x, ty) : ident * M.ptyp) =
      push env x (`Local ty)
  end

  module Var = struct
    let proj = function
      | `Global x -> Some x
      | `Asset  a ->
        Some {
          vr_name = a.as_name;
          vr_type = M.Tcontainer (M.Tasset a.as_name, M.Collection);
          vr_kind = `Constant;
        }
      | _ -> None

    let lookup (env : t) (name : ident) =
      lookup_gen proj env name

    let exists (env : t) (name : ident) =
      Option.is_some (lookup env name)

    let get (env : t) (name : ident) =
      Option.get (lookup env name)

    let push (env : t) (decl : vardecl) =
      push env (unloc decl.vr_name) (`Global decl)
  end

  module Proc = struct
    let proj = function `Proc x -> Some x | _ -> None

    let lookup (env : t) (name : ident) =
      lookup_gen proj env name

    let exists (env : t) (name : ident) =
      Option.is_some (lookup env name)

    let get (env : t) (name : ident) =
      Option.get (lookup env name)
  end

  module Asset = struct
    let proj = function `Asset x -> Some x | _ -> None

    let lookup (env : t) (name : ident) =
      lookup_gen proj env name

    let exists (env : t) (name : ident) =
      Option.is_some (lookup env name)

    let get (env : t) (name : ident) =
      Option.get (lookup env name)

    let byfield (env : t) (fname : ident) =
      Option.map
        (fun nm ->
           let decl = get env nm in
           (decl, List.assoc fname decl.as_fields))
        (Mid.find_opt fname env.env_fields)

    let push (env : t) ({ as_name = nm } as decl : assetdecl) : t =
      let env = push env (unloc nm) (`Asset decl) in
      { env with env_fields =
                   List.fold_left
                     (fun fields (x, _ty) -> Mid.add x (unloc nm) fields)
                     env.env_fields decl.as_fields }
  end

  module Action = struct
    let proj = function `Action x -> Some x | _ -> None

    let lookup (env : t) (name : ident) =
      lookup_gen proj env name

    let exists (env : t) (name : ident) =
      Option.is_some (lookup env name)

    let get (env : t) (name : ident) =
      Option.get (lookup env name)

    let push (env : t) (act : actiondecl) =
      push env (unloc act.ad_name) (`Action act)
  end

  module Transition = struct
    let proj = function `Transition x -> Some x | _ -> None

    let lookup (env : t) (name : ident) =
      lookup_gen proj env name

    let exists (env : t) (name : ident) =
      Option.is_some (lookup env name)

    let get (env : t) (name : ident) =
      Option.get (lookup env name)

    let push (env : t) (td : transitiondecl) =
      push env (unloc td.td_name) (`Transition td)
  end
end

type env = Env.t

let empty : env =
  let cb (lc, error) =
    Format.eprintf "%s: %a@."
      (Location.tostring lc) pp_error_desc error in

  List.fold_left
    (fun env (name, ty) -> Env.Type.push env (name, ty))
    (Env.create cb) core_types

(* -------------------------------------------------------------------- *)
let check_and_emit_name_free (env : env) (x : M.lident) =
  let free = Env.name_free env (unloc x) in
  if not free then
    Env.emit_error env (loc x, NameIsAlreadyBound (unloc x));
  free

(* -------------------------------------------------------------------- *)
let for_container (_ : env) = function
  | PT.Collection-> M.Collection
  | PT.Queue     -> M.Queue
  | PT.Stack     -> M.Stack
  | PT.Set       -> M.Set
  | PT.Partition -> M.Partition


(* -------------------------------------------------------------------- *)
let tt_logical_operator (op : PT.logical_operator) =
  match op with
  | And   -> M.And
  | Or    -> M.Or
  | Imply -> M.Imply
  | Equiv -> M.Equiv

(* -------------------------------------------------------------------- *)
let tt_arith_operator (op : PT.arithmetic_operator) =
  match op with
  | Plus   -> M.Plus
  | Minus  -> M.Minus
  | Mult   -> M.Mult
  | Div    -> M.Div
  | Modulo -> M.Modulo

(* -------------------------------------------------------------------- *)
let tt_cmp_operator (op : PT.comparison_operator) =
  match op with
  | Equal  -> M.Equal
  | Nequal -> M.Nequal
  | Gt     -> M.Gt
  | Ge     -> M.Ge
  | Lt     -> M.Lt
  | Le     -> M.Le

(* -------------------------------------------------------------------- *)
let get_asset_method (name : string) =
  None                          (* FIXME *)

(* -------------------------------------------------------------------- *)
exception InvalidType

let rec for_type_exn (env : env) (ty : PT.type_t) : M.ptyp =
  match unloc ty with
  | Tref x -> begin
      match Env.Type.lookup env (unloc x) with
      | None ->
        Env.emit_error env (loc x, UnknownTypeName (unloc x));
        raise InvalidType
      | Some ty -> ty
    end

  | Tcontainer (ty, ctn) ->
    M.Tcontainer (for_type_exn env ty, for_container env ctn)

  | Tvset (_x, _ty) ->
    (* FIXME *)
    assert false

  | Ttuple tys ->
    M.Ttuple (List.map (for_type_exn env) tys)

let for_type (env : env) (ty : PT.type_t) : M.ptyp option =
  try Some (for_type_exn env ty) with InvalidType -> None

(* -------------------------------------------------------------------- *)
let for_literal (_env : env) (topv : PT.literal loced) : M.bval =
  let mk_sp type_ node = M.mk_sp ~loc:(loc topv) ~type_ node in

  match unloc topv with
  | Lbool b ->
    mk_sp M.vtbool (M.BVbool b)

  | Lnumber i ->
    mk_sp M.vtint (M.BVint i)

  | Lrational (n, d) ->
    mk_sp M.vtrational (M.BVrational (n, d))

  | Lstring s ->
    mk_sp M.vtstring (M.BVstring s)

  | Ltz tz ->
    mk_sp (M.vtcurrency M.Tez) (M.BVcurrency (M.Tez, tz))

  | Laddress a ->
    mk_sp M.vtaddress (M.BVaddress a)

  | Lduration d ->
    mk_sp M.vtduration (M.BVduration d)

  | Ldate d ->
    mk_sp M.vtdate (M.BVdate d)

(* -------------------------------------------------------------------- *)
let rec for_xexpr (env : env) ?(ety : M.ptyp option) (tope : PT.expr) : xexpr =
  let module E = struct exception Bailout end in

  let bailout = fun () -> raise E.Bailout in

  let mk_sp type_ node = M.mk_sp ~loc:(loc tope) ?type_ node in
  let dummy type_ : M.pterm = mk_sp type_ (M.Pvar (mkloc (loc tope) "<error>")) in

  let doit () =
    match unloc tope with
    | Eterm (None, None, x) -> begin
        match Env.lookup env (unloc x) with
        | Some (`Local xty) ->
          `Expr (mk_sp (Some xty) (M.Pvar x))

        | Some (`Global decl) ->
          `Expr (mk_sp (Some decl.vr_type) (M.Pvar x))

        | _ ->
          Env.emit_error env (loc x, UnknownLocalOrVariable (unloc x));
          bailout ()
      end

    | Eliteral v ->
      let v = for_literal env (mkloc (loc tope) v) in
      `Expr (mk_sp v.M.type_ (M.Plit v))

    | Earray [] -> begin
        match ety with
        | Some (M.Tcontainer (_, _)) ->
          `Expr (mk_sp ety (M.Parray []))

        | _ ->
          Env.emit_error env (loc tope, CannotInferCollectionType);
          bailout ()
      end

    | Earray (e :: es) -> begin
        let elty = Option.bind (Option.map fst |@ Type.as_container) ety in
        let e    = for_expr env ?ety:elty e in
        let elty = if Option.is_some e.type_ then e.type_ else elty in
        let es   = List.map (fun e -> for_expr env ?ety:elty e) es in

        match ety with
        | Some (M.Tcontainer (_, _)) ->
          `Expr (mk_sp ety (M.Parray es))

        | _ ->
          Env.emit_error env (loc tope, CannotInferCollectionType);
          bailout ()
      end

    | Erecord fields -> begin
        let module E = struct
          type state = {
            hasupdate : bool;
            fields    : ident list;
            anon      : bool;
          }

          let state0 = {
            hasupdate = false; fields = []; anon = false;
          }
        end in

        let is_update = function
          | (None | Some (PT.ValueAssign, _)) -> false
          |  _ -> true in

        let infos = List.fold_left (fun state (fname, _) ->
            E.{ hasupdate = state.hasupdate || is_update fname;
                fields    = Option.fold
                    (fun names (_, name)-> unloc name :: names)
                    state.fields fname;
                anon      = state.anon || Option.is_none fname; })
            E.state0 fields in

        if infos.E.hasupdate then
          Env.emit_error env (loc tope, OpInRecordLiteral);

        if infos.E.anon && not (List.is_empty (infos.E.fields)) then begin
          Env.emit_error env (loc tope, MixedAnonInRecordLiteral);
          bailout ()
        end;

        if infos.E.anon || List.is_empty fields then
          match Option.map Type.as_asset ety with
          | None | Some None ->
            Env.emit_error env (loc tope, CannotInferAnonRecord);
            bailout ()

          | Some (Some asset) ->
            let asset = Env.Asset.get env (unloc asset) in
            let ne, ng = List.length fields, List.length asset.as_fields in

            if ne <> ng then begin
              Env.emit_error env (loc tope, InvalidFieldsCountInRecordLiteral);
              bailout ()
            end;

            let fields =
              List.map2 (fun (_, fe) (_, fty) ->
                  for_expr env ~ety:fty fe
                ) fields asset.as_fields;
            in `Expr (mk_sp ety (M.Precord fields))

        else begin
          let fmap =
            List.fold_left (fun fmap (fname, e) ->
                let fname = unloc (snd (Option.get fname)) in

                Mid.update fname (function
                    | None -> begin
                        let asset = Env.Asset.byfield env fname in
                        if Option.is_none asset then begin
                          let err = UnknownFieldName fname in
                          Env.emit_error env (loc tope, err)
                        end; Some (asset, [e])
                      end

                    | Some (asset, es) ->
                      if List.length es = 1 then begin
                        let err = DuplicatedFieldInRecordLiteral fname in
                        Env.emit_error env (loc tope, err)
                      end; Some (asset, e :: es)) fmap
              ) Mid.empty fields
          in

          let assets =
            List.undup id (Mid.fold (fun _ (asset, _) assets ->
                Option.fold
                  (fun assets (asset, _) -> asset :: assets)
                  assets asset
              ) fmap []) in

          let assets = List.sort Pervasives.compare assets in

          let fields =
            Mid.map (fun (asset, es) ->
                let aty = Option.map snd asset in
                List.map (fun e -> for_expr env ?ety:aty e) es
              ) fmap in

          let record =
            match assets with
            | [] ->
              bailout ()

            | _ :: _ :: _ ->
              let err =
                MixedFieldNamesInRecordLiteral
                  (List.map (fun x -> unloc x.as_name) assets)
              in Env.emit_error env (loc tope, err); bailout ()

            | [asset] ->
              let fields =
                List.map (fun (fname, ftype) ->
                    match Mid.find_opt fname fields with
                    | None ->
                      let err = MissingFieldInRecordLiteral fname in
                      Env.emit_error env (loc tope, err); dummy (Some ftype)
                    | Some thisf ->
                      List.hd (List.rev thisf))
                  asset.as_fields
              in mk_sp (Some (M.Tasset asset.as_name)) (M.Precord fields)

          in `Expr record
        end
      end

    | Etuple es -> begin
        let etys =
          match Option.bind Type.as_tuple ety with
          | Some etys when List.length etys = List.length es ->
            List.map Option.some etys
          | _ ->
            List.make (fun _ -> None) (List.length es) in

        let es = List.map2 (fun ety e -> for_expr env ?ety e) etys es in
        let ty = Option.get_all (List.map (fun x -> x.M.type_) es) in
        let ty = Option.map (fun x -> M.Ttuple x) ty in

        `Expr (mk_sp ty (M.Ptuple es))
      end

    | Edot (pe, x) -> begin
        let e = for_expr env pe in

        match Option.map Type.as_asset e.M.type_ with
        | None ->
          bailout ()

        | Some None ->
          Env.emit_error env (loc pe, AssetExpected);
          bailout ()

        | Some (Some asset) -> begin
            let asset = Env.Asset.get env (unloc asset) in

            match List.Exn.assoc (unloc x) asset.as_fields with
            | None ->
              let err = UnknownField (unloc asset.as_name, unloc x) in
              Env.emit_error env (loc x, err); bailout ()

            | Some fty ->
              `Expr (mk_sp (Some fty) (M.Pdot (e, x)))
          end
      end

    | Eapp (f, args) -> begin
        match
          match f with
          | Fident x ->
            let ps = Env.Proc.lookup env (unloc x) in
            if Option.is_none ps then
              Env.emit_error env (loc x, UnknownProcedure (unloc x));
            Option.map (fun ps -> (`Named x, ps)) ps

          | Foperator { pldesc = `Spec _; plloc = loc } ->
            Env.emit_error env (loc, SpecOperatorInExpr);
            bailout ()

          | Foperator { pldesc = ((`Logical _ | `Unary _ | `Arith _ | `Cmp _) as op) } ->
            Some (`Operator op, procsig_of_operator op)
        with
        | None ->
          bailout ()

        | Some (kind, pdf) ->

          let ne, ng = List.length pdf.psl_sig, List.length args in

          let args =
            if ne <> ng then begin
              Env.emit_error env (loc tope, InvalidNumberOfArguments (ne, ng));
              bailout ()
            end else
              List.map2
                (fun arg aty -> for_arg env aty arg)
                args pdf.psl_sig in

          let aout =
            match kind with
            | `Named x ->
              M.Pcall (None, x, args)

            | `Operator (`Logical op) ->
              let args = List.map (Option.get |@ pterm_arg_as_pterm) args in
              let a1, a2 = Option.get (List.as_seq2 args) in
              M.Plogical (tt_logical_operator op, a1, a2)

            | `Operator (`Unary op) -> begin
                let args = List.map (Option.get |@ pterm_arg_as_pterm) args in
                let a1 = Option.get (List.as_seq1 args) in

                match
                  match op with
                  | PT.Not    -> `Not
                  | PT.Uplus  -> `UArith (M.Uplus)
                  | PT.Uminus -> `UArith (M.Uminus)
                with
                | `Not ->
                  M.Pnot a1

                | `UArith op ->
                  M.Puarith (op, a1)
              end

            | `Operator (`Arith op) ->

              let args = List.map (Option.get |@ pterm_arg_as_pterm) args in
              let a1, a2 = Option.get (List.as_seq2 args) in
              M.Parith (tt_arith_operator op, a1, a2)

            | `Operator (`Cmp op) ->
              let args = List.map (Option.get |@ pterm_arg_as_pterm) args in
              let a1, a2 = Option.get (List.as_seq2 args) in
              M.Pcomp (tt_cmp_operator op, a1, a2)

          in `Expr (mk_sp (Some (pdf.psl_ret)) aout)
      end

    | Emethod (_the, _m, _args) ->
      assert false

    | Eif (c, et, Some ef) -> begin
        let c    = for_expr env ~ety:M.vtbool c in
        let et   = for_expr env et in
        let ef   = for_expr env ?ety:et.type_ ef in
        let aout = mk_sp (Some M.vtbool) (M.Pif (c, et, ef)) in

        `Expr aout
      end

    | Eletin (_lv, _t, _e1, _e2, _c) ->
      assert false

    | Ematchwith (_e, _bs) ->
      assert false

    | Equantifier (_bd, _x, _e) ->
      assert false

    | Elabel _ ->
      assert false

    | Eassert   _
    | Eassign   _
    | Ebreak
    | Efailif   _
    | Efor      _
    | Eif       _
    | Erequire  _
    | Eseq      _
    | Eterm     _
    | Etransfer _
    | Einvalid ->
      Env.emit_error env (loc tope, InvalidExpression);
      bailout ()

  in

  try
    let aout = doit () in

    begin match aout, ety with
      | `Expr { type_ = Some from_ }, Some to_ ->
        if not (Type.compatible ~from_ ~to_) then
          Env.emit_error env (loc tope, IncompatibleTypes (from_, to_));
      | _, Some to_ ->
        Env.emit_error env (loc tope, ExpressionExpected)
      | _, _ ->
        () end;

    aout

  with E.Bailout -> `Expr (dummy ety)

(* -------------------------------------------------------------------- *)
and for_expr (env : env) ?(ety : M.type_ option) (tope : PT.expr) : M.pterm =
  let mk_sp type_ node = M.mk_sp ~loc:(loc tope) ?type_ node in

  match for_xexpr env ?ety tope with
  | `Expr e ->
    e

  | _ ->
    Env.emit_error env (loc tope, ExpressionExpected);
    mk_sp ety (M.Pvar (mkloc (loc tope) "<error>"))

(* -------------------------------------------------------------------- *)
and for_arg (env : env) (ety : argtype) (tope : PT.expr) : M.pterm_arg =
  match ety with
  | `Type ety ->
    M.AExpr (for_expr env ~ety tope)

  | `Effect name ->
    M.AEffect (for_effect env name tope)

(* -------------------------------------------------------------------- *)
and for_effect (env : env) (_asset : ident) (tope : PT.expr) : effect =
  match unloc tope with
  | Erecord _fields ->
    assert false

  | _ ->
    Env.emit_error env (loc tope, InvalidEffect)

(* -------------------------------------------------------------------- *)
let for_formula (env : env) (topf : PT.expr) : M.pterm =
  let mk node = M.{ node; label = None; type_ = None; loc = loc topf; } in

  match for_xexpr env topf with
  | `Expr e ->
    Option.iter (fun ety ->
        if ety <> M.vtbool then
          Env.emit_error env (loc topf, FormulaExpected))
      e.type_; e

  | _ ->
    Env.emit_error env (loc topf, InvalidFormula);
    mk (M.Pvar (mkloc (loc topf) "<unknown>"))

(* -------------------------------------------------------------------- *)
let for_lbl_formula (env : env) (topf : PT.label_expr) : env * M.pterm =
  env, for_formula env (snd (unloc topf))

(* -------------------------------------------------------------------- *)
let for_lbls_formula (env : env) (topf : PT.label_exprs) : env * M.pterm list =
  List.fold_left_map for_lbl_formula env topf

(* -------------------------------------------------------------------- *)
let for_asset_expr (env : env) (tope : PT.expr) =
  let e = for_expr env tope in

  match Option.map Type.as_asset e.M.type_ with
  | None ->
    None

  | Some None ->
    Env.emit_error env (loc tope, InvalidAssetExpression);
    None

  | Some (Some asset) ->
    Some (Env.Asset.get env (unloc asset), e)

(* -------------------------------------------------------------------- *)
let for_arg (env : env) ((x, ty, _) : PT.lident_typ) : env =
  let ty = for_type env ty in
  let b  = check_and_emit_name_free env x in

  if b && Option.is_some ty then
    Env.Local.push env (unloc x, Option.get ty)
  else env

(* -------------------------------------------------------------------- *)
let for_args (env : env) (xs : PT.args) : env =
  List.fold_left for_arg env xs

(* -------------------------------------------------------------------- *)
let for_lvalue (env : env) (e : PT.expr) : (M.lident * M.ptyp) option =
  match unloc e with
  | Eterm (None, None, x) -> begin
      match Env.lookup env (unloc x) with
      | Some (`Local xty) ->
        Some (x, xty)

      | Some (`Global vd) ->
        if vd.vr_kind <> `Variable then
          Env.emit_error env (loc e, ReadOnlyGlobal (unloc x));
        Some (x, vd.vr_type)

      | _ ->
        Env.emit_error env (loc e, UnknownLocalOrVariable (unloc x));
        None
    end

  | _ ->
    Env.emit_error env (loc e, InvalidLValue); None

(* -------------------------------------------------------------------- *)
let for_verification_item (_env : env) (v : PT.verification_item) =
  match unloc v with
  | PT.Vpredicate (_x, _args, _e) ->
    assert false

  | PT.Vdefinition (_x, _ty, _y, _e) ->
    assert false

  | PT.Vaxiom (_x, _e) ->
    assert false

  | PT.Vtheorem (_x, _e) ->
    assert false

  | PT.Vvariable (_x, _ty, _e) ->
    assert false

  | PT.Vinvariant (_x, _lbl) ->
    assert false

  | PT.Veffect _e ->
    assert false

  | PT.Vspecification _lbl ->
    assert false

(* -------------------------------------------------------------------- *)
let for_verification (env : env) (v : PT.verification) =
  List.fold_left for_verification_item env (fst (unloc v))

(* -------------------------------------------------------------------- *)
let for_role (env : env) (name : PT.lident) =
  match Env.Var.lookup env (unloc name) with
  | None ->
    Env.emit_error env (loc name, UnknownLocalOrVariable (unloc name));
    None

  | Some nty ->
    if not (Type.compatible ~from_:nty.vr_type ~to_:M.vtrole) then
      (Env.emit_error env (loc name, NotARole (unloc name)); None)
    else Some name

(* -------------------------------------------------------------------- *)
let rec for_instruction (env : env) (i : PT.expr) : M.instruction =
  let module E = struct exception Failure end in

  let bailout () = raise E.Failure in

  let mki ?label node : M.instruction =
    M.{ label; node; type_ = None; loc = loc i; } in

  let mkseq i1 i2 =
    let asblock = function M.{ node = Iseq is } -> is | _ as i -> [i] in
    match asblock i1 @ asblock i2 with
    | [i] -> i
    | is  -> mki (Iseq is) in

  try
    match unloc i with
    | Emethod (target, name, args) -> begin
        let target = Option.get_exn E.Failure (for_asset_expr env target)  in
        let mthd   =
          match get_asset_method (unloc name) with
          | None ->
            Env.emit_error env (loc name, NoSuchMethod (unloc name));
            bailout ()
          | Some mthd -> mthd in

        assert false
      end

    | Eseq (i1, i2) ->
      let i1 = for_instruction env i1 in
      let i2 = for_instruction env i2 in
      mkseq i1 i2

    | Eassign (ValueAssign, plv, pe) -> begin
        let lv = for_lvalue env plv in
        let e  = for_expr env ?ety:(Option.map snd lv) pe in
        let x  = Option.get_dfl (mkloc (loc plv) "<error>") (Option.map fst lv) in

        begin match e.M.type_, lv with
          | Some from_, Some (_, to_) ->
            if not (Type.compatible ~from_ ~to_) then
              Env.emit_error env (loc pe, IncompatibleTypes (from_, to_))
          | _ -> () end;

        mki (M.Iassign (M.ValueAssign, x, e))
      end

    | Etransfer (e, back, to_) ->
      let to_ = Option.bind (for_role env) to_ in
      let to_ = Option.map (M.mk_id M.vtrole) to_ in
      let e   = for_expr env ~ety:(M.vtcurrency M.Tez) e in

      mki (Itransfer (e, back, to_))

    | _ ->
      Env.emit_error env (loc i, InvalidInstruction);
      bailout ()

  with E.Failure ->
    mki (Iseq [])

(* -------------------------------------------------------------------- *)
let for_named_state (env : env) (x : PT.lident) =
  let state = Env.State.byname env (unloc x) in
  if Option.is_none state then
    Env.emit_error env (loc x, UnknownState (unloc x));
  state

(* -------------------------------------------------------------------- *)
let for_state (env : env) (st : PT.expr) : ident option =
  match unloc st with
  | Eterm (None, None, x) ->
    for_named_state env x

  | _ ->
    Env.emit_error env (loc st, InvalidStateExpression);
    None

(* -------------------------------------------------------------------- *)
let for_function (env : env) (f : PT.s_function loced) : unit =
  assert false

(* -------------------------------------------------------------------- *)
let rec for_callby (env : env) (cb : PT.expr) =
  match unloc cb with
  | Eterm (None, None, name) ->
    Option.get_as_list (for_role env name)

  | Eapp (Foperator { pldesc = `Logical Or }, [e1; e2]) ->
    (for_callby env e1) @ (for_callby env e2)

  | _ ->
    Env.emit_error env (loc cb, InvalidCallByExpression);
    []

(* -------------------------------------------------------------------- *)
let for_action_properties (env : env) (act : PT.action_properties) =
  let calledby = Option.map (fun (x, _) -> for_callby env x) act.calledby in
  let env, req = Option.foldmap
      (fun env (x, _) -> for_lbls_formula env x) env act.require in
  let verif    = Option.map (for_verification env) act.verif in
  let funs     = List.map (for_function env) act.functions in

  (env, (calledby, req, verif, funs))

(* -------------------------------------------------------------------- *)
let for_effect (env : env) (effect : PT.expr) =
  for_instruction env effect

(* -------------------------------------------------------------------- *)
let for_transition (env : env) (state, when_, effect) =
  let state = for_named_state env state in
  let when_ = Option.map (fun (x, _) -> for_formula env x) when_ in
  let effect = Option.map (fun (x, _) -> for_effect env x) effect in

  (state, when_, effect)

(* -------------------------------------------------------------------- *)
let for_declaration (env : env) (decl : PT.declaration) =
  match unloc decl with
  | Darchetype _ ->
    Env.emit_error env (loc decl, InvalidArcheTypeDecl);
    env

  | Dvariable (x, ty, e, _tgts, ctt, _) ->
    (* FIXME: handle tgts *)

    let ty   = for_type env ty in
    let e    = Option.map (for_expr env ?ety:ty) e in
    let dty  = if   Option.is_some ty
      then ty
      else Option.bind (fun e -> e.M.type_) e in
    let ctt  = match ctt with
      | VKconstant -> `Constant
      | VKvariable -> `Variable in

    if Option.is_some dty then begin
      let decl = { vr_name = x; vr_type = Option.get dty; vr_kind = ctt} in

      if   (check_and_emit_name_free env x)
      then Env.Var.push env decl
      else env
    end else env

  | Denum (_x, _ctors, _) ->
    assert false

  | Dasset (x, fields, _, _, _, _) -> begin
      (* FIXME: check that there is at least one field for PK *)

      let for_field field =
        let PT.Ffield (f, fty, init, _) = unloc field in
        let fty  = for_type env fty in
        let init = Option.map (for_expr env ?ety:fty) init in
        mkloc (loc f) (unloc f, fty, init) in

      let fields = List.map for_field fields in

      Option.iter
        (fun (_, { plloc = lc; pldesc = (name, _, _) }) ->
           Env.emit_error env (lc, DuplicatedFieldInAssetDecl name))
        (List.find_dup (fun x -> proj3_1 (unloc x)) fields);

      (* FIXME: check for duplicated type name? *)

      let get_field_type { pldesc = (x, ty, e) } =
        let ty =
          if   Option.is_some ty
          then ty
          else Option.bind (fun e -> e.M.type_) e
        in Option.map (fun ty -> (x, ty)) ty
      in

      if Env.Asset.exists env (unloc x) then begin
        Env.emit_error env (loc x, DuplicatedAssetName (unloc x));
        env
      end else
        let decl = {
          as_name   = x;
          as_fields = List.pmap get_field_type fields;
        } in Env.Asset.push env decl
    end

  | Daction (x, args, _pt, i_exts, _exts) -> begin
      let env0 = for_args env args in
      let _i = Option.map (for_instruction env0) (Option.map fst i_exts) in

      Env.Action.push env { ad_name = x; }
    end

  | Dtransition (x, args, tgt, from_, actions, tx, _exts) ->
    let env0  = for_args env args in
    let from_ = for_state env from_ in
    let env, act = for_action_properties env actions in
    let tx = List.map (for_transition env) tx in

    if Option.is_some tgt then
      assert false;

    env

(*
type transition = (TO: lident * WHEN: (expr * exts) option * EFFECT: (expr * exts) option) list

type action_properties = {
  calledby        : (expr * exts) option;
  accept_transfer : bool;
  require         : (label_exprs * exts) option;
  verif           : verification option;
  functions       : (s_function loced) list;
}


*)


  | Dcontract (_x, _sig, _, _) ->
    assert false

  | Dextension (_x, _) ->
    assert false

  | Dnamespace (_x, _decls) ->
    assert false

  | Dfunction _fun ->
    assert false

  | Dverification v ->
    for_verification env v

  | Dinvalid ->
    assert false

(* -------------------------------------------------------------------- *)
type state =
  (PT.lident option * (PT.lident * PT.enum_option list option) list option)

let for_state_decl (env : env) (state : state loced) =
  (* FIXME: check that ctor names are available *)

  let name, ctors = unloc state in

  if Option.is_some name then assert false;

  match ctors with
  | None | Some [] ->
    Env.emit_error env (loc state, EmptyStateDecl);
    env, None

  | Some ctors ->
    Option.iter
      (fun (_, x) ->
         Env.emit_error env (loc x, DuplicatedCtorName (unloc x)))
      (List.find_dup unloc (List.map fst ctors));

    let ctors = List.map (snd_map (Option.get_dfl [])) ctors in
    let ctors = Mid.collect (unloc : M.lident -> ident) ctors in

    let for1 (cname, options) =
      let init, inv =
        List.fold_left (fun (init, inv) option ->
            match option with
            | PT.EOinitial ->
              (init+1, inv)
            | PT.EOspecification spec ->
              (init, List.rev_append spec inv)
          ) (0, []) options in

      if init > 1 then
        Env.emit_error env (loc cname, DuplicatedInitMarkForCtor);
      (init <> 0, List.rev inv) in

    let for1 env ((cname : PT.lident), options) =
      let init, inv = for1 (cname, options) in
      let env , inv = for_lbls_formula env inv in

      (env, (cname, init, inv)) in

    let env, ctors = List.fold_left_map for1 env ctors in

    let ictor =
      let ictors =
        List.pmap
          (fun (x, b, _) -> if b then Some x else None)
          ctors in

      match ictors with
      | [] ->
        proj3_1 (List.hd ctors)
      | init :: ictors ->
        if not (List.is_empty ictors) then
          Env.emit_error env (loc state, MultipleInitialMarker);
        init in

    env, Some (unloc ictor, List.map (fun (x, _, inv) -> (x, inv)) ctors)

(* -------------------------------------------------------------------- *)
let for_declarations (env : env) (decls : (PT.declaration list) loced) : M.model =
  let toploc = loc decls in

  match unloc decls with
  | { pldesc = Darchetype (x, _exts) } :: decls ->
    let states, subdecls =
      List.xfilter (fun decl ->
          match unloc decl with
          (* | PT.Denum (name, values, _exts_) ->
             let id = match name with | EKenum i -> Some i | EKstate -> None in
             `Left (mkloc (loc decl) (id, values)) *)  (* TODO: uncomment this with new type *)
          | x ->
            `Right (mkloc (loc decl) x)
        ) decls in

    let _decl, env =
      match states with
      | [] ->
        (None, env)

      | _ -> begin
          if List.length states > 1 then
            Env.emit_error env (toploc, MultipleStateDeclaration);

          let env =
            let for1 state =
              match for_state_decl env state with
              | env, Some state -> Some (env, state)
              | _  , None       -> None in

            match List.pmap for1 states with
            | (env, (init, ctors)) :: _ ->
              let decl = { sd_ctors = ctors; sd_init = init; } in
              (Some decl, Env.State.push env decl)
            | _ ->
              (None, env)
          in env
        end in

    let _env = List.fold_left for_declaration env subdecls in
    M.mk_model x

  | _ ->
    Env.emit_error env (loc decls, InvalidArcheTypeDecl);
    { (M.mk_model (mkloc (loc decls) "<unknown>")) with loc = loc decls }

(* -------------------------------------------------------------------- *)
let typing (env : env) (cmd : PT.archetype) =
  match unloc cmd with
  | Marchetype decls ->
    for_declarations env (mkloc (loc cmd) decls)

  | _ ->
    assert false