(**************************************************************************)
(*                                                                        *)
(*    Copyright 2012-2015 OCamlPro                                        *)
(*    Copyright 2012 INRIA                                                *)
(*                                                                        *)
(*  All rights reserved.This file is distributed under the terms of the   *)
(*  GNU Lesser General Public License version 3.0 with linking            *)
(*  exception.                                                            *)
(*                                                                        *)
(*  OPAM is distributed in the hope that it will be useful, but WITHOUT   *)
(*  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY    *)
(*  or FITNESS FOR A PARTICULAR PURPOSE.See the GNU General Public        *)
(*  License for more details.                                             *)
(*                                                                        *)
(**************************************************************************)

open OpamCompat

module type SET = sig
  include Set.S
  val map: (elt -> elt) -> t -> t
  val choose_one : t -> elt
  val of_list: elt list -> t
  val to_string: t -> string
  val to_json: t -> OpamJson.t
  val find: (elt -> bool) -> t -> elt
  val safe_add: elt -> t -> t

  module Op : sig
    val (++): t -> t -> t
    val (--): t -> t -> t
    val (%%): t -> t -> t
  end
end
module type MAP = sig
  include Map.S
  val to_string: ('a -> string) -> 'a t -> string
  val to_json: ('a -> OpamJson.t) -> 'a t -> OpamJson.t
  val keys: 'a t -> key list
  val values: 'a t -> 'a list
  val union: ('a -> 'a -> 'a) -> 'a t -> 'a t -> 'a t
  val of_list: (key * 'a) list -> 'a t
  val safe_add: key -> 'a -> 'a t -> 'a t
end
module type ABSTRACT = sig
  type t
  val of_string: string -> t
  val to_string: t -> string
  val to_json: t -> OpamJson.t
  module Set: SET with type elt = t
  module Map: MAP with type key = t
end

module type OrderedType = sig
  include Set.OrderedType
  val to_string: t -> string
  val to_json: t -> OpamJson.t
end

let max_print = 100

module OpamList = struct

  let cons x xs = x :: xs

  let concat_map ?(left="") ?(right="") ?nil sep f =
    function
    | [] -> (match nil with Some s -> s | None -> left^right)
    | l ->
      let seplen = String.length sep in
      let strs,len =
        List.fold_left (fun (strs,len) x ->
            let s = f x in s::strs, String.length s + seplen + len)
          ([],String.length left + String.length right - seplen)
          l
      in
      let buf = Bytes.create len in
      let prepend i s =
        let slen = String.length s in
        Bytes.blit_string s 0 buf (i - slen) slen;
        i - slen
      in
      let pos = prepend len right in
      let pos = prepend pos (List.hd strs) in
      let pos =
        List.fold_left (fun pos s -> prepend (prepend pos sep) s)
          pos (List.tl strs)
      in
      let pos = prepend pos left in
      assert (pos = 0);
      Bytes.to_string buf

  let to_string f =
    concat_map ~left:"{ " ~right:" }" ~nil:"{}" ", " f

  let rec remove_duplicates = function
    | a::(b::_ as r) when a = b -> remove_duplicates r
    | a::r -> a::remove_duplicates r
    | [] -> []

  let sort_nodup cmp l = remove_duplicates (List.sort cmp l)

  let filter_map f l =
    let rec loop accu = function
      | []     -> List.rev accu
      | h :: t ->
        match f h with
        | None   -> loop accu t
        | Some x -> loop (x::accu) t in
    loop [] l

  let filter_some l = filter_map (fun x -> x) l

  let insert comp x l =
    let rec aux = function
      | [] -> [x]
      | h::t when comp h x < 0 -> h::aux t
      | l -> x :: l in
    aux l

end


module Set = struct

  module Make (O : OrderedType) = struct

    module S = Set.Make(O)

    include S

    let fold f set i =
      let r = ref i in
      S.iter (fun elt ->
          r := f elt !r
        ) set;
      !r

    let choose_one s =
      match elements s with
      | [x] -> x
      | [] -> raise Not_found
      | _  -> invalid_arg "choose_one"

    let of_list l =
      List.fold_left (fun set e -> add e set) empty l

    let to_string s =
      if S.cardinal s > max_print then
        Printf.sprintf "%d elements" (S.cardinal s)
      else
        let l = S.fold (fun nv l -> O.to_string nv :: l) s [] in
        OpamList.to_string (fun x -> x) (List.rev l)

    let map f t =
      S.fold (fun e set -> S.add (f e) set) t S.empty

    let find fn s =
      choose (filter fn s)

    let to_json t =
      let elements = S.elements t in
      let jsons = List.map O.to_json elements in
      `A jsons

    module Op = struct
      let (++) = union
      let (--) = diff
      let (%%) = inter
    end

    let safe_add elt t =
      if mem elt t
      then failwith (Printf.sprintf "duplicate entry %s" (O.to_string elt))
      else add elt t
  end

end

module Map = struct

  module Make (O : OrderedType) = struct

    module M = Map.Make(O)

    include M

    let fold f map i =
      let r = ref i in
      M.iter (fun key value->
          r:= f key value !r
        ) map;
      !r

    let map f map =
      fold (fun key value map ->
          add key (f value) map
        ) map empty

    let mapi f map =
      fold (fun key value map ->
          add key (f key value) map
        ) map empty

    let values map =
      List.rev (M.fold (fun _ v acc -> v :: acc) map [])

    let keys map =
      List.rev (M.fold (fun k _ acc -> k :: acc) map [])

    let union f m1 m2 =
      M.fold (fun k v m ->
        if M.mem k m then
          M.add k (f v (M.find k m)) (M.remove k m)
        else
          M.add k v m
      ) m1 m2

    let to_string string_of_value m =
      if M.cardinal m > max_print then
        Printf.sprintf "%d elements" (M.cardinal m)
      else
        let s (k,v) = Printf.sprintf "%s:%s" (O.to_string k) (string_of_value v) in
        let l = fold (fun k v l -> s (k,v)::l) m [] in
        OpamList.to_string (fun x -> x) l

    let of_list l =
      List.fold_left (fun map (k,v) -> add k v map) empty l

    let to_json json_of_value t =
      let bindings = M.bindings t in
      let jsons = List.map (fun (k,v) ->
          `O [ ("key"  , O.to_json k);
               ("value", json_of_value v) ]
        ) bindings in
      `A jsons

    let safe_add k v map =
      if mem k map
      then failwith (Printf.sprintf "duplicate entry %s" (O.to_string k))
      else add k v map

  end

end

module AbstractString = struct
  type t = string
  let of_string x = x
  let to_string x = x
  let to_json x = `String x
  module O = struct
    type t = string
    let to_string = to_string
    let compare = compare
    let to_json = to_json
  end
  module Set = Set.Make(O)
  module Map = Map.Make(O)
end


module OInt = struct
  type t = int
  let compare = compare
  let to_string = string_of_int
  let to_json i = `String (string_of_int i)
end

module IntMap = Map.Make(OInt)
module IntSet = Set.Make(OInt)



module Option = struct
  let map f = function
    | None -> None
    | Some x -> Some (f x)

  let iter f = function
    | None -> ()
    | Some x -> f x

  let default dft = function
    | None -> dft
    | Some x -> x

  let default_map dft = function
    | None -> dft
    | some -> some

  let compare cmp o1 o2 = match o1,o2 with
    | None, None -> 0
    | Some _, None -> 1
    | None, Some _ -> -1
    | Some x1, Some x2 -> cmp x1 x2

  let to_string ?(none="") f = function
    | Some x -> f x
    | None -> none

  let some x = Some x
  let none _ = None

  let of_Not_found f x =
    try Some (f x) with Not_found -> None

  module Op = struct
    let (>>=) = function
      | None -> fun _ -> None
      | Some x -> fun f -> f x
    let (>>|) opt f = map f opt
    let (>>+) opt f = match opt with
      | None -> f ()
      | some -> some
    let (+!) opt dft = default dft opt
    let (++) = function
      | None -> fun opt -> opt
      | some -> fun _ -> some
  end
end



module OpamString = struct

  module OString = struct
    type t = string
    let compare = compare
    let to_string x = x
    let to_json x = `String x
  end

  module StringSet = Set.Make(OString)
  module StringMap = Map.Make(OString)

  module SetSet = Set.Make(StringSet)
  module SetMap = Map.Make(StringSet)

  module Set = StringSet
  module Map = StringMap

  let starts_with ~prefix s =
    let x = String.length prefix in
    let n = String.length s in
    n >= x
    && String.sub s 0 x = prefix

  let ends_with ~suffix s =
    let x = String.length suffix in
    let n = String.length s in
    n >= x
    && String.sub s (n - x) x = suffix

  let contains s c =
    try let _ = String.index s c in true
    with Not_found -> false

  let exact_match re s =
    try
      let subs = Re.exec re s in
      let subs = Array.to_list (Re.get_all_ofs subs) in
      let n = String.length s in
      let subs = List.filter (fun (s,e) -> s=0 && e=n) subs in
      List.length subs > 0
    with Not_found ->
      false

  let map f s =
    let len = String.length s in
    let b = Bytes.create len in
    for i = 0 to len - 1 do Bytes.set b i (f s.[i]) done;
    Bytes.to_string b

  let strip str =
    let p = ref 0 in
    let l = String.length str in
    let fn = function
      | ' ' | '\t' | '\r' | '\n' -> true
      | _ -> false in
    while !p < l && fn (String.unsafe_get str !p) do
      incr p;
    done;
    let p = !p in
    let l = ref (l - 1) in
    while !l >= p && fn (String.unsafe_get str !l) do
      decr l;
    done;
    String.sub str p (!l - p + 1)

  let sub_at n s =
    if String.length s <= n then
      s
    else
      String.sub s 0 n

  let remove_prefix ~prefix s =
    if starts_with ~prefix s then
      let x = String.length prefix in
      let n = String.length s in
      String.sub s x (n - x)
    else
      s

  let remove_suffix ~suffix s =
    if ends_with ~suffix s then
      let x = String.length suffix in
      let n = String.length s in
      String.sub s 0 (n - x)
    else
      s

  let cut_at_aux fn s sep =
    try
      let i = fn s sep in
      let name = String.sub s 0 i in
      let version = String.sub s (i+1) (String.length s - i - 1) in
      Some (name, version)
    with Invalid_argument _ | Not_found ->
      None

  let cut_at = cut_at_aux String.index

  let rcut_at = cut_at_aux String.rindex

  let split s c =
    Re_str.split (Re_str.regexp (Printf.sprintf "[%c]+" c)) s
  (* Unavailable in re 1.2.0 {[
       Re.(split (compile (rep1 (char c))) s
     ]} *)

  let split_delim s c =
    Re_str.split_delim (Re_str.regexp (Printf.sprintf "[%c]" c)) s
  (* Unavailable in re 1.2.0 {[
       let s = if String.length s <> 0
         then Printf.sprintf "%c%s%c" c s c
         else s in
       Re.(split (compile (rep1 (char c))) s)
     ]} *)

  let fold_left f acc s =
    let acc = ref acc in
    for i = 0 to String.length s - 1 do acc := f !acc s.[i] done;
    !acc

end



module Env = struct

  (* Remove from a c-separated list of string the one with the given prefix *)
  let reset_value ~prefix c v =
    let v = OpamString.split_delim v c in
    List.filter (fun v -> not (OpamString.starts_with ~prefix v)) v

  (* Split the list in two according to the first occurrence of the string
     starting with the given prefix.
  *)
  let cut_value ~prefix c v =
    let v = OpamString.split_delim v c in
    let rec aux before =
      function
      | [] -> [], List.rev before
      | curr::after when OpamString.starts_with ~prefix curr ->
        before, after
      | curr::after -> aux (curr::before) after
    in aux [] v

  let list =
    let lazy_env = lazy (
      let e = Unix.environment () in
      List.rev_map (fun s ->
          match OpamString.cut_at s '=' with
          | None   -> s, ""
          | Some p -> p
        ) (Array.to_list e)
    ) in
    fun () -> Lazy.force lazy_env

  let get n =
    List.assoc n (list ())

  let getopt n = try Some (get n) with Not_found -> None

end



module OpamSys = struct

  let with_process_in cmd args f =
    let path = ["/bin";"/usr/bin"] in
    let cmd =
      List.find Sys.file_exists (List.map (fun d -> Filename.concat d cmd) path)
    in
    let ic = Unix.open_process_in (cmd^" "^args) in
    try
      let r = f ic in
      ignore (Unix.close_process_in ic) ; r
    with exn ->
      ignore (Unix.close_process_in ic) ; raise exn

  let tty_out = Unix.isatty Unix.stdout

  let default_columns =
    try int_of_string (Env.get "COLUMNS") with
    | Not_found
    | Failure _ -> 80

  let get_terminal_columns () =
    try (* terminfo *)
      with_process_in "tput" "cols"
        (fun ic -> int_of_string (input_line ic))
    with Unix.Unix_error _ | Sys_error _ | Failure _ | End_of_file | Not_found ->
      try (* GNU stty *)
        with_process_in "stty" "size"
          (fun ic ->
             match OpamString.split (input_line ic) ' ' with
             | [_ ; v] -> int_of_string v
             | _ -> failwith "stty")
      with
        Unix.Unix_error _ | Sys_error _ | Failure _  | End_of_file | Not_found ->
          default_columns

  let terminal_columns =
    let v = ref (lazy (get_terminal_columns ())) in
    let () =
      try Sys.set_signal 28 (* SIGWINCH *)
            (Sys.Signal_handle
               (fun _ -> v := lazy (get_terminal_columns ())))
      with Invalid_argument _ -> ()
    in
    fun () ->
      if tty_out
      then Lazy.force !v
      else default_columns

  let home =
    let home = lazy (try Env.get "HOME" with Not_found -> Sys.getcwd ()) in
    fun () -> Lazy.force home

  let uname_s () =
    try
      with_process_in "uname" "-s"
        (fun ic -> Some (OpamString.strip (input_line ic)))
    with Unix.Unix_error _ | Sys_error _ | Not_found ->
      None

  let uname_m () =
    try
      with_process_in "uname" "-m"
        (fun ic -> Some (OpamString.strip (input_line ic)))
    with Unix.Unix_error _ | Sys_error _ | Not_found ->
      None

  type os =
    | Darwin
    | Linux
    | FreeBSD
    | OpenBSD
    | NetBSD
    | DragonFly
    | Cygwin
    | Win32
    | Unix
    | Other of string

  let os =
    let os = lazy (
      match Sys.os_type with
      | "Unix" -> begin
          match uname_s () with
          | Some "Darwin"    -> Darwin
          | Some "Linux"     -> Linux
          | Some "FreeBSD"   -> FreeBSD
          | Some "OpenBSD"   -> OpenBSD
          | Some "NetBSD"    -> NetBSD
          | Some "DragonFly" -> DragonFly
          | _                -> Unix
        end
      | "Win32"  -> Win32
      | "Cygwin" -> Cygwin
      | s        -> Other s
    ) in
    fun () -> Lazy.force os

  let arch =
    let arch =
      lazy (Option.default "Unknown" (uname_m ()))
    in
    fun () -> Lazy.force arch

  let string_of_os = function
    | Darwin    -> "darwin"
    | Linux     -> "linux"
    | FreeBSD   -> "freebsd"
    | OpenBSD   -> "openbsd"
    | NetBSD    -> "netbsd"
    | DragonFly -> "dragonfly"
    | Cygwin    -> "cygwin"
    | Win32     -> "win32"
    | Unix      -> "unix"
    | Other x   -> x

  let os_string () =
    string_of_os (os ())

  let shell_of_string = function
    | "tcsh"
    | "csh"  -> `csh
    | "zsh"  -> `zsh
    | "bash" -> `bash
    | "fish" -> `fish
    | _      -> `sh

  let guess_shell_compat () =
    try shell_of_string (Filename.basename (Env.get "SHELL"))
    with Not_found -> `sh

  let guess_dot_profile shell =
    let home f =
      try Filename.concat (home ()) f
      with Not_found -> f in
    match shell with
    | `fish ->
      List.fold_left Filename.concat (home ".config") ["fish"; "config.fish"]
    | `zsh  -> home ".zshrc"
    | `bash ->
      (try
         List.find Sys.file_exists [
           (* Bash looks up these 3 files in order and only loads the first,
              for LOGIN shells *)
           home ".bash_profile";
           home ".bash_login";
           home ".profile";
           (* Bash loads .bashrc INSTEAD, for interactive NON login shells only;
              but it's often included from the above.
              We may include our variables in both to be sure ; for now we rely
              on non-login shells inheriting their env from a login shell
              somewhere... *)
         ]
       with Not_found ->
         (* iff none of the above exist, creating this should be safe *)
         home ".bash_profile")
    | `csh ->
      let cshrc = home ".cshrc" in
      let tcshrc = home ".tcshrc" in
      if Sys.file_exists cshrc then cshrc else tcshrc
    | _     -> home ".profile"


  let registered_at_exit = ref []
  let at_exit f =
    Pervasives.at_exit f;
    registered_at_exit := f :: !registered_at_exit
  let exec_at_exit () =
    List.iter
      (fun f -> try f () with _ -> ())
      !registered_at_exit

  let path_sep =
    let path_sep = lazy (
      match os () with
      | Win32 -> ';'
      | Cygwin | _ -> ':'
    ) in
    fun () -> Lazy.force path_sep

  exception Exit of int
  exception Exec of string * string array * string array

  let exit i = raise (Exit i)
end



module OpamFormat = struct

  let visual_length_substring s ofs len =
    let rec aux s i =
      try
        let i = String.index_from s i '\027' in
        let j = String.index_from s (i+1) 'm' in
        if j > ofs + len then 0 else
          j - i + 1 + aux s (j+1)
      with Not_found | Invalid_argument _ -> 0
    in
    len - aux s ofs

  let visual_length s = visual_length_substring s 0 (String.length s)

  let indent_left s ?(visual=s) nb =
    let nb = nb - String.length visual in
    if nb <= 0 then
      s
    else
      s ^ String.make nb ' '

  let indent_right s ?(visual=s) nb =
    let nb = nb - String.length visual in
    if nb <= 0 then
      s
    else
      String.make nb ' ' ^ s

  let align_table ll =
    let rec transpose ll =
      if List.for_all ((=) []) ll then [] else
      let col, rest =
        List.fold_left (fun (col,rest) -> function
            | hd::tl -> hd::col, tl::rest
            | [] -> ""::col, []::rest)
          ([],[]) ll
      in
      List.rev col::transpose (List.rev rest)
    in
    let columns = transpose ll in
    let pad n s =
      let sn = visual_length s in
      if sn >= n then s
      else s ^ (String.make (n - sn) ' ')
    in
    let align sl =
      let len = List.fold_left (fun m s -> max m (visual_length s)) 0 sl in
      List.map (pad len) sl
    in
    transpose (List.map align columns)

  let reformat ?(start_column=0) ?(indent=0) s =
    let slen = String.length s in
    let buf = Buffer.create 1024 in
    let rec find_nonsp i =
      if i >= slen then i else
      match s.[i] with ' ' -> find_nonsp (i+1) | _ -> i
    in
    let rec find_split i =
      if i >= slen then i else
      match s.[i] with ' ' | '\n' -> i | _ -> find_split (i+1)
    in
    let newline i =
      Buffer.add_char buf '\n';
      if i+1 < slen && s.[i+1] <> '\n' then
        for _i = 1 to indent do Buffer.add_char buf ' ' done
    in
    let rec print i col =
      if i >= slen then () else
      if s.[i] = '\n' then (newline i; print (i+1) indent) else
      let j = find_nonsp i in
      let k = find_split j in
      let len_visual = visual_length_substring s i (k - i) in
      if col + len_visual >= OpamSys.terminal_columns () && col > indent then
        (newline i;
         Buffer.add_substring buf s j (k - j);
         print k (indent + len_visual - j + i))
      else
        (Buffer.add_substring buf s i (k - i);
         print k (col + len_visual))
    in
    print 0 start_column;
    Buffer.contents buf

  let itemize ?(bullet="  - ") f =
    OpamList.concat_map ~left:bullet ~right:"\n" ~nil:"" ("\n"^bullet)
      (fun s -> reformat ~indent:(String.length bullet) (f s))

  let rec pretty_list ?(last="and") = function
    | []    -> ""
    | [a]   -> a
    | [a;b] -> Printf.sprintf "%s %s %s" a last b
    | h::t  -> Printf.sprintf "%s, %s" h (pretty_list t)

  let print_table oc ~sep =
    List.iter (fun l ->
        let l = match l with s::l -> output_string oc s; l | [] -> [] in
        List.iter (fun s -> output_string oc sep; output_string oc s) l;
        output_char oc '\n')

end


module Exn = struct

  (** To use when catching default exceptions: ensures we don't catch fatal errors
      like C-c *)
  let fatal e = match e with
    | Sys.Break -> prerr_newline (); raise e
    | Assert_failure _ | Match_failure _ -> raise e
    | _ -> ()

  let register_backtrace, get_backtrace =
    let registered_backtrace = ref None in
    (fun e ->
       registered_backtrace :=
         match !registered_backtrace with
         | Some (e1, _) as reg when e1 == e -> reg
         | _ -> Some (e, Printexc.get_backtrace ())),
    (fun e ->
       match !registered_backtrace with
       | Some(e1,bt) when e1 == e -> bt
       | _ -> Printexc.get_backtrace ())

  let pretty_backtrace e =
    match get_backtrace e with
    | "" -> ""
    | b  ->
      let b =
        OpamFormat.itemize ~bullet:"  " (fun x -> x) (OpamString.split b '\n')
      in
      Printf.sprintf "Backtrace:\n%s" b

end


module Op = struct

  let (@@) f x = f x

  let (|>) x f = f x

  let (@*) g f x = g (f x)

  let (@>) f g x = g (f x)

end


module Config = struct

  module type Sig = sig

    type t
    type 'a options_fun

    val default: t
    val set: t -> (unit -> t) options_fun
    val setk: (t -> 'a) -> t -> 'a options_fun
    val r: t ref
    val update: ?noop:_ -> (unit -> unit) options_fun
    val init: ?noop:_ -> (unit -> unit)  options_fun
    val initk: 'a -> 'a options_fun

  end

  type env_var = string

  let env conv var =
    try Option.map conv (Env.getopt ("OPAM"^var))
    with Failure _ ->
      flush stdout;
      Printf.eprintf
        "[WARNING] Invalid value for environment variable OPAM%s, ignored."
        var;
      None

  let env_bool var =
    env (fun s -> match String.lowercase s with
        | "" | "0" | "no" | "false" -> false
        | "1" | "yes" | "true" -> true
        | _ -> failwith "env_bool")
      var

  let env_int var = env int_of_string var

  let env_level var =
    env (fun s -> match String.lowercase s with
        | "" | "no" | "false" -> 0
        | "yes" | "true" -> 1
        | s -> int_of_string s)
      var

  let env_string var =
    env (fun s -> s) var

  let env_float var =
    env float_of_string var

  let when_ext s =
    match String.lowercase s with
    | "extended" -> `Extended
    | "always" -> `Always
    | "never" -> `Never
    | "auto" -> `Auto
    | _ -> failwith "env_when"

  let env_when_ext var = env when_ext var

  let env_when var =
    env (fun v -> match when_ext v with
        | (`Always | `Never | `Auto) as w -> w
        | `Extended -> failwith "env_when")
      var

  let resolve_when ~auto = function
    | `Always -> true
    | `Never -> false
    | `Auto -> Lazy.force auto

  let initk k =
    let utf8 = Option.Op.(
        env_when_ext "UTF8" ++
        (env_bool "UTF8MSGS" >>= function
          | true -> Some `Extended
          | false -> None)
      ) in
    let answer = match env_bool "YES", env_bool "NO" with
      | Some true, _ -> Some (Some true)
      | _, Some true -> Some (Some false)
      | None, None -> None
      | _ -> Some None
    in
    OpamCoreConfig.(setk (setk (fun c -> r := c; k)) !r)
      ?debug_level:(env_level "DEBUG")
      ?verbose_level:(env_level "VERBOSE")
      ?color:(env_when "COLOR")
      ?utf8
      ?disp_status_line:(env_when "STATUSLINE")
      ?answer
      ?safe_mode:(env_bool "SAFE")
      ?lock_retries:(env_int "LOCKRETRIES")
      ?log_dir:(env_string "LOGS")
      ?keep_log_dir:(env_bool "KEEPLOGS")
      ?errlog_length:(env_int "ERRLOGLEN")

  let init ?noop:_ = initk (fun () -> ())
end

module List = OpamList
module String = OpamString
module Sys = OpamSys
module Format = OpamFormat
