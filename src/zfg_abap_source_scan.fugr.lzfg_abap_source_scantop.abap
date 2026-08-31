*&---------------------------------------------------------------------*
*& Include  LZFG_ABAP_SOURCE_SCANTOP                    Function Group
*&---------------------------------------------------------------------*
*& Core logic of the ABAP source code scan.
*&
*& The scan engine lives here so that it is owned by the function group
*& and is reachable only through the RFC enabled function module
*& Z_ABAP_SOURCE_SCAN. Every other development must call that function
*& module - no other program should duplicate this logic.
*&---------------------------------------------------------------------*
FUNCTION-POOL zfg_abap_source_scan.

*----------------------------------------------------------------------*
*  Types
*----------------------------------------------------------------------*
TYPES: ty_source_line TYPE c LENGTH 255,
       tt_source      TYPE STANDARD TABLE OF ty_source_line
                           WITH DEFAULT KEY.

TYPES: tt_scan_selopt TYPE STANDARD TABLE OF zsabap_scan_selopt
                           WITH DEFAULT KEY,
       tt_scan_result TYPE STANDARD TABLE OF zsabap_scan_result
                           WITH NON-UNIQUE KEY include line_no,
       tt_needle      TYPE STANDARD TABLE OF string
                           WITH DEFAULT KEY.

TYPES: BEGIN OF ty_search,
         fieldname     TYPE zabap_source_scan-fieldname,
         search_value  TYPE zabap_source_scan-existing_value,
         replace_value TYPE zabap_source_scan-replace_value,
       END OF ty_search,
       tt_search TYPE STANDARD TABLE OF ty_search WITH DEFAULT KEY.

TYPES: BEGIN OF ty_r_object,
         sign   TYPE ddsign,
         option TYPE ddoption,
         low    TYPE tadir-object,
         high   TYPE tadir-object,
       END OF ty_r_object,
       tt_r_object TYPE STANDARD TABLE OF ty_r_object WITH DEFAULT KEY.

TYPES: BEGIN OF ty_object,
         object   TYPE tadir-object,
         obj_name TYPE tadir-obj_name,
         devclass TYPE tadir-devclass,
       END OF ty_object,
       tt_object TYPE STANDARD TABLE OF ty_object WITH DEFAULT KEY.

TYPES: BEGIN OF ty_include,
         object   TYPE tadir-object,
         obj_name TYPE tadir-obj_name,
         devclass TYPE tadir-devclass,
         include  TYPE trdir-name,
       END OF ty_include,
       tt_include TYPE STANDARD TABLE OF ty_include WITH DEFAULT KEY.

CONSTANTS: gc_obj_prog TYPE tadir-object VALUE 'PROG',
           gc_obj_clas TYPE tadir-object VALUE 'CLAS',
           gc_obj_intf TYPE tadir-object VALUE 'INTF',
           gc_obj_fugr TYPE tadir-object VALUE 'FUGR'.

*----------------------------------------------------------------------*
*  Scan engine
*----------------------------------------------------------------------*
CLASS lcl_source_scan DEFINITION FINAL.

  PUBLIC SECTION.

    METHODS constructor
      IMPORTING
        iv_search_string  TYPE zabap_source_scan-existing_value
        iv_fieldname      TYPE zabap_source_scan-fieldname
        it_devclass       TYPE tt_scan_selopt
        iv_scan_prog      TYPE xfeld
        iv_scan_clas      TYPE xfeld
        iv_scan_fugr      TYPE xfeld
        iv_case_sensitive TYPE xfeld
        iv_skip_comments  TYPE xfeld
        iv_max_hits       TYPE int4.

    "! Determines the search values, expands the object list and scans.
    METHODS run
      EXPORTING
        ev_failed  TYPE xfeld
        ev_message TYPE string.

    METHODS get_results
      RETURNING VALUE(rt_result) TYPE tt_scan_result.

    METHODS get_search_values
      RETURNING VALUE(rt_search) TYPE tt_search.

    METHODS is_limit_reached
      RETURNING VALUE(rv_reached) TYPE xfeld.

  PRIVATE SECTION.

    DATA: mv_search_string  TYPE zabap_source_scan-existing_value,
          mv_fieldname      TYPE zabap_source_scan-fieldname,
          mt_devclass       TYPE tt_scan_selopt,
          mv_scan_prog      TYPE xfeld,
          mv_scan_clas      TYPE xfeld,
          mv_scan_fugr      TYPE xfeld,
          mv_case_sensitive TYPE xfeld,
          mv_skip_comments  TYPE xfeld,
          mv_max_hits       TYPE int4,
          mv_limit_reached  TYPE xfeld.

    DATA: mt_search  TYPE tt_search,
          mt_needle  TYPE tt_needle,
          mt_object  TYPE tt_object,
          mt_include TYPE tt_include,
          mt_result  TYPE tt_scan_result.

    METHODS determine_search_values
      EXPORTING
        ev_failed  TYPE xfeld
        ev_message TYPE string.

    METHODS build_needles.

    METHODS collect_objects
      EXPORTING
        ev_failed  TYPE xfeld
        ev_message TYPE string.

    METHODS expand_includes.

    METHODS expand_program_includes
      IMPORTING it_object TYPE tt_object.

    METHODS expand_class_includes
      IMPORTING it_object TYPE tt_object.

    METHODS scan_includes.

    METHODS scan_single_include
      IMPORTING is_include TYPE ty_include.

    METHODS remove_duplicates.

    METHODS is_comment_line
      IMPORTING iv_line          TYPE ty_source_line
      RETURNING VALUE(rv_result) TYPE xfeld.

    METHODS class_pool_prefix
      IMPORTING iv_name          TYPE tadir-obj_name
                iv_suffix        TYPE c
      RETURNING VALUE(rv_prefix) TYPE trdir-name.

    METHODS function_group_program
      IMPORTING iv_area           TYPE tadir-obj_name
      RETURNING VALUE(rv_program) TYPE trdir-name.

    METHODS show_progress
      IMPORTING iv_current TYPE i
                iv_total   TYPE i
                iv_text    TYPE string.

ENDCLASS.

*----------------------------------------------------------------------*
CLASS lcl_source_scan IMPLEMENTATION.

  METHOD constructor.
    mv_search_string  = iv_search_string.
    mv_fieldname      = iv_fieldname.
    mt_devclass       = it_devclass.
    mv_scan_prog      = iv_scan_prog.
    mv_scan_clas      = iv_scan_clas.
    mv_scan_fugr      = iv_scan_fugr.
    mv_case_sensitive = iv_case_sensitive.
    mv_skip_comments  = iv_skip_comments.
    mv_max_hits       = iv_max_hits.
    IF mv_max_hits <= 0.
      mv_max_hits = 10000.
    ENDIF.
  ENDMETHOD.

  METHOD run.

    CLEAR: ev_failed, ev_message.

    determine_search_values( IMPORTING ev_failed  = ev_failed
                                       ev_message = ev_message ).
    IF ev_failed = abap_true.
      RETURN.
    ENDIF.

    build_needles( ).

    collect_objects( IMPORTING ev_failed  = ev_failed
                               ev_message = ev_message ).
    IF ev_failed = abap_true.
      RETURN.
    ENDIF.

    expand_includes( ).

    IF mt_include IS INITIAL.
      ev_failed  = abap_true.
      ev_message = 'No source code found for the selected packages'.
      RETURN.
    ENDIF.

    scan_includes( ).
    remove_duplicates( ).

    IF mt_result IS INITIAL.
      ev_failed  = abap_true.
      ev_message = 'No occurrences found for the given search criteria'.
    ENDIF.

  ENDMETHOD.

*----------------------------------------------------------------------*
*  Scenario 1: search string supplied -> use it directly
*  Scenario 2: search string blank    -> read ZABAP_SOURCE_SCAN
*----------------------------------------------------------------------*
  METHOD determine_search_values.

    DATA: ls_search TYPE ty_search,
          lt_config TYPE STANDARD TABLE OF zabap_source_scan,
          ls_config TYPE zabap_source_scan.

    CLEAR: ev_failed, ev_message, mt_search.

    IF mv_search_string IS NOT INITIAL.

      ls_search-fieldname    = mv_fieldname.
      ls_search-search_value = mv_search_string.

      " the replacement value is informational only - read it when the
      " combination happens to be maintained in the configuration table
      IF mv_fieldname IS NOT INITIAL.
        SELECT SINGLE replace_value
          FROM zabap_source_scan
          INTO ls_search-replace_value
          WHERE fieldname      = mv_fieldname
            AND existing_value = mv_search_string.
        IF sy-subrc <> 0.
          CLEAR ls_search-replace_value.
        ENDIF.
      ENDIF.

      APPEND ls_search TO mt_search.
      RETURN.

    ENDIF.

    IF mv_fieldname IS INITIAL.
      ev_failed  = abap_true.
      ev_message = 'Enter a search string or a field name'.
      RETURN.
    ENDIF.

    SELECT * FROM zabap_source_scan
      INTO TABLE lt_config
      WHERE fieldname = mv_fieldname.
    IF sy-subrc <> 0.
      ev_failed  = abap_true.
      CONCATENATE 'No entries in ZABAP_SOURCE_SCAN for field'
                  mv_fieldname
             INTO ev_message SEPARATED BY space.
      RETURN.
    ENDIF.

    LOOP AT lt_config INTO ls_config.
      IF ls_config-existing_value IS INITIAL.
        CONTINUE.
      ENDIF.
      CLEAR ls_search.
      ls_search-fieldname     = ls_config-fieldname.
      ls_search-search_value  = ls_config-existing_value.
      ls_search-replace_value = ls_config-replace_value.
      APPEND ls_search TO mt_search.
    ENDLOOP.

    SORT mt_search BY fieldname search_value.
    DELETE ADJACENT DUPLICATES FROM mt_search
           COMPARING fieldname search_value.

    IF mt_search IS INITIAL.
      ev_failed  = abap_true.
      ev_message = 'No usable EXISTING_VALUE maintained for this field'.
    ENDIF.

  ENDMETHOD.

*----------------------------------------------------------------------*
*  The search strings are prepared once, not per source code line.
*----------------------------------------------------------------------*
  METHOD build_needles.

    DATA: ls_search TYPE ty_search,
          lv_needle TYPE string.

    CLEAR mt_needle.

    LOOP AT mt_search INTO ls_search.
      lv_needle = ls_search-search_value.
      SHIFT lv_needle LEFT DELETING LEADING space.
      APPEND lv_needle TO mt_needle.
    ENDLOOP.

  ENDMETHOD.

*----------------------------------------------------------------------*
*  Object list from TADIR for the requested packages
*----------------------------------------------------------------------*
  METHOD collect_objects.

    DATA: lt_objtype TYPE tt_r_object,
          ls_objtype TYPE ty_r_object.

    CLEAR: ev_failed, ev_message, mt_object.

    ls_objtype-sign   = 'I'.
    ls_objtype-option = 'EQ'.

    IF mv_scan_prog = abap_true.
      ls_objtype-low = gc_obj_prog.
      APPEND ls_objtype TO lt_objtype.
    ENDIF.
    IF mv_scan_clas = abap_true.
      ls_objtype-low = gc_obj_clas.
      APPEND ls_objtype TO lt_objtype.
      ls_objtype-low = gc_obj_intf.
      APPEND ls_objtype TO lt_objtype.
    ENDIF.
    IF mv_scan_fugr = abap_true.
      ls_objtype-low = gc_obj_fugr.
      APPEND ls_objtype TO lt_objtype.
    ENDIF.

    IF lt_objtype IS INITIAL.
      ev_failed  = abap_true.
      ev_message = 'Select at least one object type to be scanned'.
      RETURN.
    ENDIF.

    SELECT object obj_name devclass
      FROM tadir
      INTO TABLE mt_object
      WHERE pgmid    = 'R3TR'
        AND object   IN lt_objtype
        AND devclass IN mt_devclass
        AND delflag  = space.

    IF sy-subrc <> 0 OR mt_object IS INITIAL.
      ev_failed  = abap_true.
      ev_message = 'No repository objects found for the selected packages'.
      RETURN.
    ENDIF.

    SORT mt_object BY object obj_name.

  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD expand_includes.

    DATA: lt_main  TYPE tt_object,
          lt_class TYPE tt_object,
          ls_obj   TYPE ty_object.

    CLEAR mt_include.

    LOOP AT mt_object INTO ls_obj.
      CASE ls_obj-object.
        WHEN gc_obj_prog OR gc_obj_fugr.
          APPEND ls_obj TO lt_main.
        WHEN gc_obj_clas OR gc_obj_intf.
          APPEND ls_obj TO lt_class.
      ENDCASE.
    ENDLOOP.

    expand_program_includes( lt_main ).
    expand_class_includes( lt_class ).

    SORT mt_include BY include object obj_name.
    DELETE ADJACENT DUPLICATES FROM mt_include COMPARING include.

  ENDMETHOD.

*----------------------------------------------------------------------*
*  Programs and function groups: master program + all its includes
*----------------------------------------------------------------------*
  METHOD expand_program_includes.

    TYPES: BEGIN OF ty_master,
             object   TYPE tadir-object,
             obj_name TYPE tadir-obj_name,
             devclass TYPE tadir-devclass,
             master   TYPE trdir-name,
           END OF ty_master.

    TYPES: BEGIN OF ty_d010inc,
             master  TYPE trdir-name,
             include TYPE trdir-name,
           END OF ty_d010inc.

    DATA: lt_master  TYPE STANDARD TABLE OF ty_master WITH DEFAULT KEY,
          ls_master  TYPE ty_master,
          ls_obj     TYPE ty_object,
          ls_include TYPE ty_include.

    DATA: lt_d010inc TYPE STANDARD TABLE OF ty_d010inc WITH DEFAULT KEY,
          ls_d010inc TYPE ty_d010inc.

    IF it_object IS INITIAL.
      RETURN.
    ENDIF.

    LOOP AT it_object INTO ls_obj.
      CLEAR ls_master.
      ls_master-object   = ls_obj-object.
      ls_master-obj_name = ls_obj-obj_name.
      ls_master-devclass = ls_obj-devclass.

      IF ls_obj-object = gc_obj_fugr.
        ls_master-master = function_group_program( ls_obj-obj_name ).
      ELSE.
        ls_master-master = ls_obj-obj_name.
      ENDIF.

      IF ls_master-master IS INITIAL.
        CONTINUE.
      ENDIF.

      APPEND ls_master TO lt_master.

      " the master program itself is scanned as well
      CLEAR ls_include.
      ls_include-object   = ls_obj-object.
      ls_include-obj_name = ls_obj-obj_name.
      ls_include-devclass = ls_obj-devclass.
      ls_include-include  = ls_master-master.
      APPEND ls_include TO mt_include.
    ENDLOOP.

    IF lt_master IS INITIAL.
      RETURN.
    ENDIF.

    SELECT master include
      FROM d010inc
      INTO TABLE lt_d010inc
      FOR ALL ENTRIES IN lt_master
      WHERE master = lt_master-master.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    SORT lt_master BY master.

    LOOP AT lt_d010inc INTO ls_d010inc.
      READ TABLE lt_master INTO ls_master
           WITH KEY master = ls_d010inc-master BINARY SEARCH.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.
      CLEAR ls_include.
      ls_include-object   = ls_master-object.
      ls_include-obj_name = ls_master-obj_name.
      ls_include-devclass = ls_master-devclass.
      ls_include-include  = ls_d010inc-include.
      APPEND ls_include TO mt_include.
    ENDLOOP.

  ENDMETHOD.

*----------------------------------------------------------------------*
*  Classes and interfaces: all generated includes of the class /
*  interface pool (=====CP, =====CU/CO/CI, =====CM*, =====CCDEF ...)
*----------------------------------------------------------------------*
  METHOD expand_class_includes.

    CONSTANTS: lc_prefix_len TYPE i VALUE 31,
               lc_high_char  TYPE c VALUE '~'.

    TYPES: BEGIN OF ty_prefix,
             prefix   TYPE trdir-name,
             object   TYPE tadir-object,
             obj_name TYPE tadir-obj_name,
             devclass TYPE tadir-devclass,
           END OF ty_prefix.

    TYPES: BEGIN OF ty_r_name,
             sign   TYPE ddsign,
             option TYPE ddoption,
             low    TYPE trdir-name,
             high   TYPE trdir-name,
           END OF ty_r_name.

    DATA: lt_prefix  TYPE STANDARD TABLE OF ty_prefix WITH DEFAULT KEY,
          ls_prefix  TYPE ty_prefix,
          lt_range   TYPE STANDARD TABLE OF ty_r_name WITH DEFAULT KEY,
          ls_range   TYPE ty_r_name,
          ls_obj     TYPE ty_object,
          ls_include TYPE ty_include,
          lv_prefix  TYPE trdir-name,
          lv_high    TYPE trdir-name,
          lv_fill    TYPE i.

    DATA: lt_names TYPE STANDARD TABLE OF trdir-name WITH DEFAULT KEY,
          lv_name  TYPE trdir-name,
          lv_key   TYPE trdir-name.

    IF it_object IS INITIAL.
      RETURN.
    ENDIF.

    LOOP AT it_object INTO ls_obj.

      IF ls_obj-object = gc_obj_intf.
        lv_prefix = class_pool_prefix( iv_name   = ls_obj-obj_name
                                       iv_suffix = 'I' ).
      ELSE.
        lv_prefix = class_pool_prefix( iv_name   = ls_obj-obj_name
                                       iv_suffix = 'C' ).
      ENDIF.

      IF lv_prefix IS INITIAL.
        CONTINUE.
      ENDIF.

      CLEAR ls_prefix.
      ls_prefix-prefix   = lv_prefix.
      ls_prefix-object   = ls_obj-object.
      ls_prefix-obj_name = ls_obj-obj_name.
      ls_prefix-devclass = ls_obj-devclass.
      APPEND ls_prefix TO lt_prefix.

*     all generated includes of the pool start with the 31 character
*     prefix, so they lie in the interval
*     [ prefix + blanks .. prefix + high value characters ]
      lv_high = lv_prefix.
      lv_fill = lc_prefix_len.
      WHILE lv_fill < 40.
        lv_high+lv_fill(1) = lc_high_char.
        lv_fill = lv_fill + 1.
      ENDWHILE.

      CLEAR ls_range.
      ls_range-sign   = 'I'.
      ls_range-option = 'BT'.
      ls_range-low    = lv_prefix.
      ls_range-high   = lv_high.
      APPEND ls_range TO lt_range.

    ENDLOOP.

    IF lt_range IS INITIAL.
      RETURN.
    ENDIF.

    SELECT name
      FROM trdir
      INTO TABLE lt_names
      WHERE name IN lt_range.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    SORT lt_prefix BY prefix.

    LOOP AT lt_names INTO lv_name.
      lv_key = lv_name(lc_prefix_len).
      READ TABLE lt_prefix INTO ls_prefix
           WITH KEY prefix = lv_key BINARY SEARCH.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.
      CLEAR ls_include.
      ls_include-object   = ls_prefix-object.
      ls_include-obj_name = ls_prefix-obj_name.
      ls_include-devclass = ls_prefix-devclass.
      ls_include-include  = lv_name.
      APPEND ls_include TO mt_include.
    ENDLOOP.

  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD scan_includes.

    DATA: ls_include TYPE ty_include,
          lv_total   TYPE i,
          lv_current TYPE i,
          lv_text    TYPE string.

    CLEAR: mt_result, mv_limit_reached.

    lv_total = lines( mt_include ).
    lv_text  = 'Scanning ABAP source code'.

    LOOP AT mt_include INTO ls_include.
      lv_current = sy-tabix.

      IF lv_current MOD 200 = 0.
        show_progress( iv_current = lv_current
                       iv_total   = lv_total
                       iv_text    = lv_text ).
      ENDIF.

      scan_single_include( ls_include ).

      IF mv_limit_reached = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.

*----------------------------------------------------------------------*
*  One include is read once and checked against ALL search values.
*  This keeps the number of READ REPORT calls independent of the number
*  of EXISTING_VALUE entries in the configuration table.
*----------------------------------------------------------------------*
  METHOD scan_single_include.

    DATA: lt_source TYPE tt_source,
          lv_line   TYPE ty_source_line,
          lv_index  TYPE i,
          ls_search TYPE ty_search,
          ls_result TYPE zsabap_scan_result,
          lv_needle TYPE string,
          lv_tabix  TYPE i,
          lv_hits   TYPE i.

    READ REPORT ls_include-include INTO lt_source.
    IF sy-subrc <> 0 OR lt_source IS INITIAL.
      RETURN.
    ENDIF.

    LOOP AT lt_source INTO lv_line.
      lv_index = sy-tabix.

      IF lv_line IS INITIAL.
        CONTINUE.
      ENDIF.

      IF mv_skip_comments = abap_true.
        IF is_comment_line( lv_line ) = abap_true.
          CONTINUE.
        ENDIF.
      ENDIF.

      LOOP AT mt_search INTO ls_search.

        lv_tabix = sy-tabix.
        READ TABLE mt_needle INTO lv_needle INDEX lv_tabix.
        IF sy-subrc <> 0 OR lv_needle IS INITIAL.
          CONTINUE.
        ENDIF.

        IF mv_case_sensitive = abap_true.
          FIND FIRST OCCURRENCE OF lv_needle IN lv_line RESPECTING CASE.
        ELSE.
          FIND FIRST OCCURRENCE OF lv_needle IN lv_line IGNORING CASE.
        ENDIF.
        IF sy-subrc <> 0.
          CONTINUE.
        ENDIF.

        CLEAR ls_result.
        ls_result-fieldname     = ls_search-fieldname.
        ls_result-search_value  = ls_search-search_value.
        ls_result-replace_value = ls_search-replace_value.
        ls_result-devclass      = ls_include-devclass.
        ls_result-object        = ls_include-object.
        ls_result-obj_name      = ls_include-obj_name.
        ls_result-include       = ls_include-include.
        ls_result-line_no       = lv_index.
        ls_result-source_line   = lv_line.
        APPEND ls_result TO mt_result.

        lv_hits = lines( mt_result ).
        IF lv_hits >= mv_max_hits.
          mv_limit_reached = abap_true.
          RETURN.
        ENDIF.

      ENDLOOP.
    ENDLOOP.

  ENDMETHOD.

*----------------------------------------------------------------------*
*  A hit is identified by include + line + search value. The search
*  value stays part of the key so that a line containing two different
*  configured values is reported once per value.
*----------------------------------------------------------------------*
  METHOD remove_duplicates.

    SORT mt_result BY devclass object obj_name include line_no
                      fieldname search_value.

    DELETE ADJACENT DUPLICATES FROM mt_result
           COMPARING include line_no fieldname search_value.

  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD is_comment_line.

    DATA: lv_work TYPE ty_source_line,
          lv_len  TYPE i.

    rv_result = abap_false.

    lv_len = strlen( iv_line ).
    IF lv_len = 0.
      RETURN.
    ENDIF.

    " full line comment - asterisk in column 1
    IF iv_line(1) = '*'.
      rv_result = abap_true.
      RETURN.
    ENDIF.

    " line that only contains a quote comment
    lv_work = iv_line.
    SHIFT lv_work LEFT DELETING LEADING space.
    lv_len = strlen( lv_work ).
    IF lv_len > 0.
      IF lv_work(1) = '"'.
        rv_result = abap_true.
      ENDIF.
    ENDIF.

  ENDMETHOD.

*----------------------------------------------------------------------*
*  ZCL_TEST -> ZCL_TEST======================C   (30 characters + 'C')
*  the generated includes are ...CP / ...CU / ...CM001 / ...CCDEF etc.
*----------------------------------------------------------------------*
  METHOD class_pool_prefix.

    DATA: lv_name30 TYPE c LENGTH 30,
          lv_len    TYPE i.

    CLEAR rv_prefix.

    lv_len = strlen( iv_name ).
    IF lv_len = 0 OR lv_len > 30.
      RETURN.
    ENDIF.

    lv_name30 = iv_name.
    TRANSLATE lv_name30 USING ' ='.

    CONCATENATE lv_name30 iv_suffix INTO rv_prefix.

  ENDMETHOD.

*----------------------------------------------------------------------*
*  ZFG_TEST     -> SAPLZFG_TEST
*  /NS/ZFG_TEST -> /NS/SAPLZFG_TEST
*----------------------------------------------------------------------*
  METHOD function_group_program.

    DATA: lv_area   TYPE string,
          lv_offset TYPE i,
          lv_len    TYPE i.

    CLEAR rv_program.

    lv_area = iv_area.
    CONDENSE lv_area.
    IF lv_area IS INITIAL.
      RETURN.
    ENDIF.

    IF lv_area(1) = '/'.
      FIND '/' IN lv_area+1 MATCH OFFSET lv_offset.
      IF sy-subrc <> 0.
        RETURN.
      ENDIF.
      lv_len = lv_offset + 2.
      CONCATENATE lv_area(lv_len) 'SAPL' lv_area+lv_len INTO rv_program.
    ELSE.
      CONCATENATE 'SAPL' lv_area INTO rv_program.
    ENDIF.

  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD show_progress.

    DATA: lv_percent TYPE i,
          lv_text    TYPE c LENGTH 100.

    IF sy-batch = abap_true OR iv_total <= 0.
      RETURN.
    ENDIF.

    lv_percent = iv_current * 100 / iv_total.
    lv_text    = iv_text.

    CALL FUNCTION 'SAPGUI_PROGRESS_INDICATOR'
      EXPORTING
        percentage = lv_percent
        text       = lv_text.

  ENDMETHOD.

*----------------------------------------------------------------------*
  METHOD get_results.
    rt_result = mt_result.
  ENDMETHOD.

  METHOD get_search_values.
    rt_search = mt_search.
  ENDMETHOD.

  METHOD is_limit_reached.
    rv_reached = mv_limit_reached.
  ENDMETHOD.

ENDCLASS.
