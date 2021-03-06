(* L1 Compiler
 * Top Level Environment
 * Author: Kaustuv Chaudhuri <kaustuv+@cs.cmu.edu>
 * Modified: Alex Vaynberg <alv@andrew.cmu.edu>
 * Modified: Frank Pfenning <fp@cs.cmu.edu>
 *)

signature TOP =
sig
  (* main function for standalone executable
   * use with SMLofNJ.exportFn("heapfilename", Top.main)
   *)
  val main : string * string list -> OS.Process.status
  
  (* test "arguments"; is the same as executing a saved
   * heap with arguments on the command line
   *)
  val test : string -> OS.Process.status
end

structure Top :> TOP =
struct
  structure G = GetOpt  (* from $/smlnj-lib/Util/getopt-sig.sml *)

  fun say s = TextIO.output (TextIO.stdErr, s ^ "\n")

  fun newline () = TextIO.output (TextIO.stdErr, "\n")

  exception EXIT

  (* see flag explanations below *)
  val flag_verbose = Flag.flag "verbose"
  val flag_ast = Flag.flag "ast"
  val flag_ir = Flag.flag "ir"
  val flag_assem = Flag.flag "assem"

  fun reset_flags () =
      List.app Flag.unset [flag_verbose, flag_ast,
			   flag_ir, flag_assem];

  val options = [{short = "v", long=["verbose"], 
		  desc=G.NoArg (fn () => Flag.set flag_verbose),
		  help="verbose messages"},
		 {short = "", long=["dump-ast"],
		  desc=G.NoArg (fn () => Flag.set flag_ast),
		  help="pretty print the AST"},
		 {short = "", long=["dump-ir"],
		  desc=G.NoArg (fn () => Flag.set flag_ir),
		  help="pretty print the IR"},
		 {short = "", long=["dump-assem"],
		  desc=G.NoArg (fn () => Flag.set flag_assem),
		  help="pretty print the assembly before register allocaction"}
		]


  fun stem s =
      let
	  val (prefix, suffix) =
	      Substring.splitr (fn c => c <> #".") (Substring.full s)
      in
	  if Substring.isEmpty prefix (* no "." in string s *)
	     then s (* return whole string *)
	  else Substring.string (Substring.trimr 1 prefix)
      end

  fun main (name, args) =
      let
	val header = "Usage: compile [OPTION...] SOURCEFILE\nwhere OPTION is"
	val usageinfo = G.usageInfo {header = header, options = options}
	fun errfn msg = (say (msg ^ "\n" ^ usageinfo) ; raise EXIT)

	val _ = Temp.reset (); (* reset temp variable counter *)
	val _ = reset_flags (); (* return all flags to default value *)

	val _ = if List.length args = 0 then
		    (say usageinfo; raise EXIT)
		else ()

	val (opts, files) =
	    G.getOpt {argOrder = G.Permute,
		      options = options,
		      errFn = errfn}
		     args

	val source =
	    case files
	      of [] => errfn "Error: no input file"
	       | [filename] => filename
	       | _ => errfn "Error: more than one input file"

	val _ = Flag.guard flag_verbose say ("Parsing... " ^ source)
	val ast = Parse.parse source
	val _ = Flag.guard flag_ast
		  (fn () => say (Ast.Print.pp_program ast)) ()

	val _ = Flag.guard flag_verbose say "Checking..."
	val _ = TypeChecker.typecheck ast

	val _ = Flag.guard flag_verbose say "Translating..."
	val ir = Trans.translate ast
	val _ = Flag.guard flag_ir (fn () => say (Tree.Print.pp_program ir)) ()

	val _ = Flag.guard flag_verbose say "Codegen..."
	val assem = Codegen.codegen ir
	val _ = Flag.guard flag_assem
		  (fn () => List.app (TextIO.print o Assem.format) assem) ()

	val assem = [Assem.DIRECTIVE(".file\t\"" ^ source ^ "\"")]
		    @ assem
		    @ [Assem.DIRECTIVE ".ident\t\"15-411 L1 reference compiler\""]
	val code = String.concat (List.map (Assem.format) assem)

	val afname = stem source ^ ".s"
	val _ = Flag.guard flag_verbose say ("Writing assembly to " ^ afname ^ " ...")
	val _ = SafeIO.withOpenOut afname (fn afstream =>
		   TextIO.output (afstream, code))
      in
	  OS.Process.success
      end
      handle ErrorMsg.Error => ( say "Compilation failed" ; OS.Process.failure )
	   | EXIT => OS.Process.failure
(*
           | e => (say ("Unrecognized exception " ^ exnMessage e); OS.Process.failure)
*)

  fun test s = main ("", String.tokens Char.isSpace s)
end
