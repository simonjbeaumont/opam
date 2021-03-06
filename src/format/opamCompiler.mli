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

(** Compiler names and versions *)

(** OCaml compiler versions *)
module Version: sig

  include OpamStd.ABSTRACT

  (** Compiler constraint *)
  type constr = (OpamFormula.relop * t) OpamFormula.formula

  (** Compare OCaml versions *)
  val compare: t -> t -> int

  (** Evaluate a relational operator between OCaml versions *)
  val eval_relop: OpamFormula.relop -> t -> t -> bool
end

(** Compiler names *)
include OpamStd.ABSTRACT

(** Return the compiler version *)
val version: t -> Version.t

(** Convert a filename into a compiler name. This function extract
    [name] from {i /path/to/$name.comp}. *)
val of_filename: OpamFilename.t -> t option

(** List the compiler available in the global state. *)
val list: OpamFilename.Dir.t -> Set.t

(** List the compiler available in a directory (and their prefix) *)
val prefixes: OpamFilename.Dir.t -> string option Map.t

(** System compiler *)
val system: t
