# ZABAP_SOURCE_SCAN — Custom ABAP Source Code Scan

Configurable search of ABAP source code, driven either by a search string
entered on the selection screen or by values maintained in the custom
configuration table `ZABAP_SOURCE_SCAN`.

The **core logic sits in the RFC enabled function module
`Z_ABAP_SOURCE_SCAN`**. The report is only a user interface on top of it,
so any other development can reuse the identical logic with one
`CALL FUNCTION` instead of copying code.

* Transport : **S2AK901133**
* Package   : **ZUTILITY**

---

## 1. Objects

| Object | Type | Description |
| ------ | ---- | ----------- |
| `ZABAP_SOURCE_SCAN`   | Table (TRANSP)  | Search / replace configuration |
| `ZSABAP_SCAN_SELOPT`  | Structure       | Package range for the RFC interface |
| `ZSABAP_SCAN_RESULT`  | Structure       | One result line of the RFC interface |
| `ZFG_ABAP_SOURCE_SCAN`| Function group  | Holds the scan engine (TOP include) |
| `Z_ABAP_SOURCE_SCAN`  | Function module | **RFC enabled** — the reusable API |
| `ZABAP_SOURCE_SCAN`   | Report          | Selection screen + ALV, calls the RFC |

Repository layout:

```
/.abapgit.xml
/src/zabap_source_scan.tabl.xml
/src/zsabap_scan_selopt.tabl.xml
/src/zsabap_scan_result.tabl.xml
/src/zfg_abap_source_scan.fugr.xml
/src/zfg_abap_source_scan.fugr.lzfg_abap_source_scantop.abap   " scan engine
/src/zfg_abap_source_scan.fugr.lzfg_abap_source_scantop.xml
/src/zfg_abap_source_scan.fugr.saplzfg_abap_source_scan.abap
/src/zfg_abap_source_scan.fugr.saplzfg_abap_source_scan.xml
/src/zfg_abap_source_scan.fugr.z_abap_source_scan.abap         " FM body
/src/zabap_source_scan.prog.abap
/src/zabap_source_scan.prog.xml
```

Import with abapGit (online repo, or *New Offline* → *Import ZIP*), assign
package `ZUTILITY`, and pull. Activation order matters and abapGit handles
it: DDIC objects → function group → report.

> If abapGit reports a problem on the function group, create it manually —
> it takes two minutes. SE80 → create function group `ZFG_ABAP_SOURCE_SCAN`,
> paste `…lzfg_abap_source_scantop.abap` into the TOP include, then SE37 →
> create `Z_ABAP_SOURCE_SCAN`, tick **Remote-Enabled Module**, key in the
> interface from section 3 below, and paste `…z_abap_source_scan.abap` as
> the body. Everything else imports normally.

---

## 2. Configuration table `ZABAP_SOURCE_SCAN`

| Field            | Type                 | Key | Description |
| ---------------- | -------------------- | --- | ----------- |
| `MANDT`          | `MANDT` (CLNT3)      | X   | Client |
| `FIELDNAME`      | `FIELDNAME` (CHAR30) | X   | SAP field name (`BUKRS`, `WERKS`, …) |
| `EXISTING_VALUE` | CHAR60               | X   | Value to be searched in the source code |
| `REPLACE_VALUE`  | CHAR60               |     | Corresponding replacement value |

Delivery class **C** (customizing), maintenance **allowed**, buffering off.
`FIELDNAME` + `EXISTING_VALUE` are both key fields, so one field name can
carry any number of values.

After the pull, generate the maintenance dialog once in **SE11 →
ZABAP_SOURCE_SCAN → Utilities → Table Maintenance Generator** (one step,
screen 0001). The table can then be maintained with **SM30**.

Example content:

| FIELDNAME | EXISTING_VALUE | REPLACE_VALUE |
| --------- | -------------- | ------------- |
| `BUKRS`   | `1000`         | `2000`        |
| `BUKRS`   | `1100`         | `2100`        |
| `WERKS`   | `BA01`         | `BB01`        |
| `SHKZG`   | `S`            | `H`           |

`REPLACE_VALUE` is configuration data only. **Nothing ever changes source
code** — occurrences are identified and the configured replacement is shown
next to each hit.

---

## 3. The RFC — `Z_ABAP_SOURCE_SCAN`

Function group `ZFG_ABAP_SOURCE_SCAN`, **Remote-Enabled Module**, all
scalar parameters pass by value, all types are Dictionary types.

**Import**

| Parameter | Type | Default | Description |
| --------- | ---- | ------- | ----------- |
| `IV_SEARCH_STRING`  | `ZABAP_SOURCE_SCAN-EXISTING_VALUE` | – | Search string; blank = read from configuration |
| `IV_FIELDNAME`      | `ZABAP_SOURCE_SCAN-FIELDNAME` | – | Configuration field name |
| `IV_SCAN_PROG`      | `XFELD` | `'X'` | Scan programs / includes |
| `IV_SCAN_CLAS`      | `XFELD` | `'X'` | Scan classes / interfaces |
| `IV_SCAN_FUGR`      | `XFELD` | `'X'` | Scan function groups |
| `IV_CASE_SENSITIVE` | `XFELD` | `SPACE` | Case-sensitive search |
| `IV_SKIP_COMMENTS`  | `XFELD` | `'X'` | Ignore comment lines |
| `IV_MAX_HITS`       | `INT4`  | `10000` | Hit limit |

**Export**

| Parameter | Type | Description |
| --------- | ---- | ----------- |
| `EV_SUBRC`          | `SYSUBRC`  | 0 = hits returned, 4 = nothing found / input error |
| `EV_MESSAGE`        | `BAPI_MSG` | Reason when `EV_SUBRC` = 4 |
| `EV_LIMIT_REACHED`  | `XFELD`    | `'X'` = `IV_MAX_HITS` was hit, result is incomplete |

**Tables**

| Parameter | Structure | Description |
| --------- | --------- | ----------- |
| `IT_PACKAGE` | `ZSABAP_SCAN_SELOPT` | Package range (`SIGN`/`OPTION`/`LOW`/`HIGH`); empty ⇒ `Z*` and `Y*` |
| `ET_RESULT`  | `ZSABAP_SCAN_RESULT` | The hits |

### Calling it from another development

```abap
DATA: lt_package TYPE STANDARD TABLE OF zsabap_scan_selopt WITH DEFAULT KEY,
      ls_package TYPE zsabap_scan_selopt,
      lt_result  TYPE STANDARD TABLE OF zsabap_scan_result WITH DEFAULT KEY,
      lv_subrc   TYPE sysubrc,
      lv_message TYPE bapi_msg.

ls_package-sign   = 'I'.
ls_package-option = 'EQ'.
ls_package-low    = 'ZFI_UTIL'.
APPEND ls_package TO lt_package.

CALL FUNCTION 'Z_ABAP_SOURCE_SCAN'          " add DESTINATION for a remote system
  EXPORTING
    iv_fieldname = 'BUKRS'                  " values come from the config table
  IMPORTING
    ev_subrc     = lv_subrc
    ev_message   = lv_message
  TABLES
    it_package   = lt_package
    et_result    = lt_result.
```

Leave `IT_PACKAGE` empty to fall back to `Z*` / `Y*`. Pass
`IV_SEARCH_STRING` instead of `IV_FIELDNAME` for a direct one-off search.

---

## 4. Search logic (inside the RFC)

```
IV_SEARCH_STRING filled ?
   YES -> that string is the only search value.
          If IV_FIELDNAME is also given, the matching REPLACE_VALUE is
          read from ZABAP_SOURCE_SCAN for information.
   NO  -> IV_FIELDNAME is mandatory.
          SELECT * FROM zabap_source_scan WHERE fieldname = IV_FIELDNAME
          Every EXISTING_VALUE becomes a search value.
          Empty values are skipped, duplicates are removed.
```

**Package default** — when `IT_PACKAGE` is empty the function module builds
the range `I CP Z*` / `I CP Y*`, so *every* caller gets the same default.

---

## 5. Scan engine

The engine lives in include `LZFG_ABAP_SOURCE_SCANTOP` (local class
`LCL_SOURCE_SCAN`) and reproduces the behaviour of the standard
**ABAP Source Scan** (`RS_ABAP_SOURCE_SCAN`):

1. `TADIR` supplies the object list (`PGMID = 'R3TR'`, object type in
   PROG / CLAS / INTF / FUGR, `DEVCLASS` in the package range,
   `DELFLAG = space`).
2. Every object is expanded into its includes:
   * programs — the program itself plus all includes from `D010INC`;
   * function groups — `SAPL<area>` (namespace aware) plus its includes;
   * classes/interfaces — every generated include of the pool
     (`…CP`, `…CU`, `…CO`, `…CI`, `…CM001`, `…CCDEF`, `…CCIMP`, `…CCAU`, …),
     found through an interval selection on `TRDIR-NAME`.
3. The include list is sorted and deduplicated, so every include is read
   **exactly once**.
4. `READ REPORT` loads the source and each line is matched against **all**
   search values in one pass (`FIND … RESPECTING/IGNORING CASE`).
5. Comment lines (`*` in column 1, or a line that only holds a `"` comment)
   are skipped when `IV_SKIP_COMMENTS` is set.

The report's checkbox **Call Standard ABAP Source Scan** bypasses all of
this and hands over to `RS_ABAP_SOURCE_SCAN` through its own selection
screen; the program name is passed dynamically, so the report still
compiles on systems where that report is missing.

---

## 6. Output

`ET_RESULT` / the report's `GT_RESULT`, displayed with `CL_SALV_TABLE`:

| Column | Meaning |
| ------ | ------- |
| `FIELDNAME` | Configuration field name |
| `SEARCH_VALUE` | Value that produced the hit |
| `REPLACE_VALUE` | Configured replacement (information only) |
| `DEVCLASS` | Package |
| `OBJECT` | Object type (PROG / CLAS / INTF / FUGR) |
| `OBJ_NAME` | Repository object |
| `INCLUDE` | Include / program actually containing the line |
| `LINE_NO` | Line number inside the include |
| `SOURCE_LINE` | The source code line |

The ALV title shows the number of hits; all standard ALV functions (sort,
filter, layout, export) are on.

**Duplicate handling** — results are sorted by
`DEVCLASS / OBJECT / OBJ_NAME / INCLUDE / LINE_NO / FIELDNAME / SEARCH_VALUE`
and deduplicated on `INCLUDE / LINE_NO / FIELDNAME / SEARCH_VALUE`. A line
containing two different configured values is therefore reported once per
value — which is what identifies *which* value was found.

---

## 7. Error handling and validation

* Report, `AT SELECTION-SCREEN`: a search string or a field name is
  required, at least one object type must be selected, `P_MAX` must not be
  negative.
* RFC: returns `EV_SUBRC = 4` plus `EV_MESSAGE` for — no configuration
  entries for the field name, no usable `EXISTING_VALUE`, no repository
  objects in the packages, no source found, no occurrences. The report
  shows the message as `MESSAGE … TYPE 'S' DISPLAY LIKE 'E'`.
* `READ REPORT` failures on a single include are ignored, so one broken
  object cannot abort the run.
* ALV exceptions (`CX_SALV_MSG`, `CX_SALV_NOT_FOUND`) are caught.

---

## 8. Performance notes

* One `TADIR` select and one `D010INC` / `TRDIR` select for the whole run —
  no per-object database round trips.
* The include list is deduplicated, so a shared include is read once.
* Each include is read once and matched against **all** search values, so
  runtime is independent of the number of `EXISTING_VALUE` entries.
* Search strings are prepared once before the scan, not per source line.
* `IV_MAX_HITS` stops the scan as soon as the limit is reached.
* Progress indicator every 200 includes (dialog mode only).
* For a full `Z*` / `Y*` scan on a large system, run the report in
  **background**.
