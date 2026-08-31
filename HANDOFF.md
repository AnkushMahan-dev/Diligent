# Handoff — ZABAP_SOURCE_SCAN

Context for continuing this work in Claude Code on the desktop, including
pushing this repository to GitHub.

* Target repo : `https://github.com/AnkushMahan-dev/Diligent.git` (private, currently **empty** — no commits, no default branch)
* SAP transport : **S2AK901133**
* SAP package : **ZUTILITY**
* Import method : abapGit

---

## 1. What was asked for

Build a custom ABAP source code scan whose search values are configurable in
a Z table, then refactor so the core logic lives in an RFC-enabled function
module that other developments can reuse, and finally push everything to the
GitHub repo above.

Original requirement, in full:

1. **Custom Z table** `ZABAP_SOURCE_SCAN` with `MANDT`, `FIELDNAME`,
   `EXISTING_VALUE`, `REPLACE_VALUE`. Multiple entries allowed per
   `FIELDNAME` (e.g. `BUKRS/1000/2000`, `BUKRS/1100/2100`, `WERKS/BA01/BB01`,
   `SHKZG/S/H`). This table drives what is searched for and what the
   replacement would be.
2. **Custom report** `ZABAP_SOURCE_SCAN` using the standard
   `RS_ABAP_SOURCE_SCAN` functionality. Selection screen: **Search String**
   (optional), **Field Name** (optional), **Package** (optional).
3. **Default package selection** — when no package is entered, search only
   `Z*` and `Y*`.
4. **Search logic**
   * Search String entered → use it directly.
   * Search String blank → read `ZABAP_SOURCE_SCAN` by `FIELDNAME`, take every
     `EXISTING_VALUE`, and scan for each one in turn.
5. **Use the standard SAP ABAP Source Scan** rather than an independent
   search mechanism; handle multiple search strings sequentially.
6. **Output** in an internal table with the same information the standard scan
   returns — object, include, line number, source line, package, search value
   — combined into one table across all search values, displayed in ALV.
7. Both manual and configuration-driven search must work; all three selection
   fields optional per the scenarios; duplicates handled; `REPLACE_VALUE`
   shown but **no source code is ever changed**; clean ABAP practices; error
   handling and validation; performance considered for many `EXISTING_VALUE`
   entries.

Follow-up requirement: **core logic must sit in an RFC** so the same logic can
be called from other developments, and the report must call that RFC.
Decision taken: local call only, no `DESTINATION` parameter on the selection
screen (the FM is still remote-enabled, so callers can add one).

---

## 2. What was built

| Object | Type | Role |
| ------ | ---- | ---- |
| `ZABAP_SOURCE_SCAN`    | Table (TRANSP, delivery class C) | Search / replace configuration |
| `ZSABAP_SCAN_SELOPT`   | Structure (INTTAB) | Package range for the RFC interface |
| `ZSABAP_SCAN_RESULT`   | Structure (INTTAB) | One result line for the RFC interface |
| `ZFG_ABAP_SOURCE_SCAN` | Function group | Scan engine, in the TOP include |
| `Z_ABAP_SOURCE_SCAN`   | Function module, **RFC enabled** | The reusable API |
| `ZABAP_SOURCE_SCAN`    | Report | Selection screen + ALV, calls the RFC |

Full functional and technical documentation is in `README.md` in this
repository — object list, table fields, the RFC interface with a caller
snippet, search logic, scan engine, output columns, duplicate handling, error
handling and performance notes. Read that first.

---

## 3. Two open decisions the next session should know about

**a) The scan does not `SUBMIT RS_ABAP_SOURCE_SCAN`.**

Requirement 5 asked for the standard program to be used. The ADT connection
(`abap-adt` MCP server) returned **HTTP 401 on every call** for the whole
session, so the standard program's selection-screen parameter names could not
be read off the system. Hardcoding guessed names would either short-dump at
runtime or silently scan the entire repository unrestricted, so instead the
engine reproduces what the standard scan does:

```
TADIR (PGMID R3TR, object PROG/CLAS/INTF/FUGR, DEVCLASS in range, DELFLAG = space)
  -> includes:  programs & function groups via D010INC
                classes/interfaces via an interval selection on TRDIR-NAME
  -> dedupe include list
  -> READ REPORT, match every line against all search values in one pass
```

The report's checkbox **Call Standard ABAP Source Scan** (`P_STD`) hands over
to `RS_ABAP_SOURCE_SCAN` through its own selection screen; the program name is
passed dynamically (`SUBMIT (lv_report) VIA SELECTION-SCREEN AND RETURN`) so
the report still compiles where that program is absent.

*To finish this properly:* once ADT login works, read
`RS_ABAP_SOURCE_SCAN`'s source, note the real selection-screen parameter
names, and either wire a `SUBMIT ... WITH ...` into the function module or
confirm the current engine is the better fit. The engine is isolated in
`LCL_SOURCE_SCAN` inside `LZFG_ABAP_SOURCE_SCANTOP`, so swapping it is a
contained change.

**b) The abapGit XML was hand-built; three format bugs are now fixed.**

**The dump was `.abapgit.xml`.** It had an `<abapGit version="v1.0.0" ...>`
wrapper element around `<asx:abap>`. Object files under `/src/` do use that
wrapper, but `.abapgit.xml` must **not**: `zcl_abapgit_dot_abapgit=>from_xml`
runs `CALL TRANSFORMATION id` straight on the raw file, so its root element
has to be `<asx:abap>` itself. With the wrapper, asXML reports "the root tag
<abap> must be in the XML namespace http://www.sap.com/abapxml" - reason 1 of
the dump.

That method has no `TRY`/`CATCH`, which is why it short-dumped instead of
showing an abapGit error. Object XML is read through
`zif_abapgit_xml_input~read`, which *does* catch `cx_transformation_error` and
raises a readable "File <name>: ..." message - so a short dump in `FROM_XML`
can only come from `.abapgit.xml`. Reference: abapGit's own `.abapgit.xml`.

Two further ordering bugs were found and fixed in the same pass (they would
have surfaced as abapGit error messages after the dump was cleared):

abapGit reads object files with `CALL TRANSFORMATION id`, and asXML requires
every element to appear **in the component order of the underlying ABAP
structure**; out-of-order elements are reported as "start tags appear where no
more are expected":

* `zfg_abap_source_scan.fugr.xml` - all eight `RSIMP` blocks had `TYP` before
  `OPTIONAL`. Correct order is `PARAMETER, DEFAULT, OPTIONAL, TYP`.
* `zabap_source_scan.prog.xml` - `PROGDIR` had `VARCL` after `SUBC`. In
  `PROGDIR`, `VARCL` is component 5 and `SUBC` is component 11.

Both are fixed. Every XML file was then re-checked mechanically against the
real component orders, taken from abapGit's own repository: `deps/dd03p`,
`deps/progdir`, `deps/dd02v` and `deps/dd09l` for the DDIC objects, and the
serialized function group `src/objects/core/zabapgit_parallel.fugr.xml` for
the FUGR layout (which also confirms the row element names - `<SOBJ_NAME>`
under `INCLUDES`, `<item>` under `FUNCTIONS`, `<RSIMP>`/`<RSEXP>`/`<RSTBL>`
under the parameter tables). All seven files now pass.

That is a static check against known-good reference files, not an import into
a real system - the fallback below still stands if the FUGR step fails.

*If the FUGR step of the pull fails:* create it by hand — SE80, new function
group `ZFG_ABAP_SOURCE_SCAN`, paste
`src/zfg_abap_source_scan.fugr.lzfg_abap_source_scantop.abap` into the TOP
include; SE37, new function module `Z_ABAP_SOURCE_SCAN`, tick
**Remote-Enabled Module**, key in the interface from README section 3, paste
`src/zfg_abap_source_scan.fugr.z_abap_source_scan.abap` as the body. Then
re-pull; everything else imports normally.

---

## 4. Also still to do in the system

* **Table maintenance generator** for `ZABAP_SOURCE_SCAN` — SE11 → Utilities →
  Table Maintenance Generator (one step, screen 0001), so the table can be
  maintained with SM30. Not serializable by abapGit; do it once after import.
* Assign all objects to package **ZUTILITY** and transport **S2AK901133**
  during the abapGit pull.
* Nothing has been created in the SAP system yet — the 401 blocked every
  write. Everything in this repo is source only.

---

## 5. Repository layout

```
/.abapgit.xml                                                  starting folder /src/, prefix logic
/README.md                                                     full documentation
/HANDOFF.md                                                    this file
/src/zabap_source_scan.tabl.xml                                config table
/src/zsabap_scan_selopt.tabl.xml                               RFC package-range structure
/src/zsabap_scan_result.tabl.xml                               RFC result structure
/src/zfg_abap_source_scan.fugr.xml                             function group + FM interface
/src/zfg_abap_source_scan.fugr.lzfg_abap_source_scantop.abap   >> the scan engine
/src/zfg_abap_source_scan.fugr.lzfg_abap_source_scantop.xml
/src/zfg_abap_source_scan.fugr.saplzfg_abap_source_scan.abap
/src/zfg_abap_source_scan.fugr.saplzfg_abap_source_scan.xml
/src/zfg_abap_source_scan.fugr.z_abap_source_scan.abap         RFC function module body
/src/zabap_source_scan.prog.abap                               report (calls the RFC)
/src/zabap_source_scan.prog.xml                                report attributes + texts
```

---

## 6. Pushing to GitHub

The repo is empty, so this is the first commit. From the unzipped folder:

```bash
cd <folder containing .abapgit.xml, README.md, HANDOFF.md and src/>
git init
git add .
git commit -m "ZABAP_SOURCE_SCAN: config table, RFC scan engine and ALV report"
git branch -M main
git remote add origin https://github.com/AnkushMahan-dev/Diligent.git
git push -u origin main
```

Then in abapGit: **New Online** → that URL → package `ZUTILITY` → pull, and
record the objects on **S2AK901133**.
