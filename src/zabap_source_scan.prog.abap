*&---------------------------------------------------------------------*
*& Report  ZABAP_SOURCE_SCAN
*&---------------------------------------------------------------------*
*& Custom ABAP Source Code Scan with configurable search / replace values
*&
*& Package     : ZUTILITY
*&
*& This report is only the user interface. The complete scan logic lives
*& in the RFC enabled function module
*&
*&      Z_ABAP_SOURCE_SCAN     (function group ZFG_ABAP_SOURCE_SCAN)
*&
*& so that any other development can reuse exactly the same logic by
*& calling that function module instead of copying code.
*&
*& Behaviour
*&   Search String entered  -> that string is used for the scan.
*&   Search String blank    -> all EXISTING_VALUE entries of the given
*&                             FIELD NAME are read from the configuration
*&                             table ZABAP_SOURCE_SCAN and each one is
*&                             scanned for.
*&   Package blank          -> the function module restricts the scan to
*&                             packages Z* and Y*.
*&
*&   REPLACE_VALUE is configuration data and is only displayed. No source
*&   code is ever changed.
*&---------------------------------------------------------------------*
REPORT zabap_source_scan.

TABLES tadir.

*----------------------------------------------------------------------*
*  Types
*----------------------------------------------------------------------*
TYPES: tt_result TYPE STANDARD TABLE OF zsabap_scan_result
                      WITH NON-UNIQUE KEY include line_no,
       tt_selopt TYPE STANDARD TABLE OF zsabap_scan_selopt
                      WITH DEFAULT KEY.

CONSTANTS gc_std_scan TYPE trdir-name VALUE 'RS_ABAP_SOURCE_SCAN'.

*----------------------------------------------------------------------*
*  Selection screen
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE text-t01.
PARAMETERS     p_srch TYPE zabap_source_scan-existing_value.
PARAMETERS     p_fld  TYPE zabap_source_scan-fieldname.
SELECT-OPTIONS s_devc FOR tadir-devclass.
SELECTION-SCREEN END OF BLOCK b1.

SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE text-t02.
PARAMETERS p_prog AS CHECKBOX DEFAULT 'X'.
PARAMETERS p_clas AS CHECKBOX DEFAULT 'X'.
PARAMETERS p_fugr AS CHECKBOX DEFAULT 'X'.
SELECTION-SCREEN END OF BLOCK b2.

SELECTION-SCREEN BEGIN OF BLOCK b3 WITH FRAME TITLE text-t03.
PARAMETERS p_case AS CHECKBOX.
PARAMETERS p_comm AS CHECKBOX DEFAULT 'X'.
PARAMETERS p_max  TYPE int4 DEFAULT 10000.
PARAMETERS p_std  AS CHECKBOX.
SELECTION-SCREEN END OF BLOCK b3.

*----------------------------------------------------------------------*
*  ALV output
*----------------------------------------------------------------------*
CLASS lcl_alv DEFINITION FINAL.

  PUBLIC SECTION.
    CLASS-METHODS display
      IMPORTING iv_title  TYPE string
      CHANGING  ct_result TYPE tt_result.

  PRIVATE SECTION.
    CLASS-METHODS set_text
      IMPORTING io_columns TYPE REF TO cl_salv_columns_table
                iv_column  TYPE lvc_fname
                iv_short   TYPE scrtext_s
                iv_medium  TYPE scrtext_m
                iv_long    TYPE scrtext_l.

ENDCLASS.

*----------------------------------------------------------------------*
CLASS lcl_alv IMPLEMENTATION.

  METHOD display.

    DATA: lo_alv     TYPE REF TO cl_salv_table,
          lo_columns TYPE REF TO cl_salv_columns_table,
          lo_display TYPE REF TO cl_salv_display_settings,
          lo_msg     TYPE REF TO cx_salv_msg,
          lv_text    TYPE string.

    TRY.
        cl_salv_table=>factory(
          IMPORTING r_salv_table = lo_alv
          CHANGING  t_table      = ct_result ).
      CATCH cx_salv_msg INTO lo_msg.
        lv_text = lo_msg->get_text( ).
        MESSAGE lv_text TYPE 'S' DISPLAY LIKE 'E'.
        RETURN.
    ENDTRY.

    lo_alv->get_functions( )->set_all( abap_true ).

    lo_columns = lo_alv->get_columns( ).
    lo_columns->set_optimize( abap_true ).

    set_text( io_columns = lo_columns iv_column = 'FIELDNAME'
              iv_short = 'Field'     iv_medium = 'Field Name'
              iv_long  = 'Configuration Field Name' ).
    set_text( io_columns = lo_columns iv_column = 'SEARCH_VALUE'
              iv_short = 'Search'    iv_medium = 'Search Value'
              iv_long  = 'Searched Value' ).
    set_text( io_columns = lo_columns iv_column = 'REPLACE_VALUE'
              iv_short = 'Replace'   iv_medium = 'Replace Value'
              iv_long  = 'Configured Replacement Value' ).
    set_text( io_columns = lo_columns iv_column = 'DEVCLASS'
              iv_short = 'Package'   iv_medium = 'Package'
              iv_long  = 'Package' ).
    set_text( io_columns = lo_columns iv_column = 'OBJECT'
              iv_short = 'Type'      iv_medium = 'Object Type'
              iv_long  = 'Object Type' ).
    set_text( io_columns = lo_columns iv_column = 'OBJ_NAME'
              iv_short = 'Object'    iv_medium = 'Object Name'
              iv_long  = 'Repository Object Name' ).
    set_text( io_columns = lo_columns iv_column = 'INCLUDE'
              iv_short = 'Include'   iv_medium = 'Include'
              iv_long  = 'Include / Program' ).
    set_text( io_columns = lo_columns iv_column = 'LINE_NO'
              iv_short = 'Line'      iv_medium = 'Line Number'
              iv_long  = 'Source Line Number' ).
    set_text( io_columns = lo_columns iv_column = 'SOURCE_LINE'
              iv_short = 'Source'    iv_medium = 'Source Line'
              iv_long  = 'ABAP Source Code Line' ).

    lo_display = lo_alv->get_display_settings( ).
    lo_display->set_striped_pattern( abap_true ).
    lo_display->set_list_header( iv_title ).

    lo_alv->display( ).

  ENDMETHOD.

  METHOD set_text.

    DATA lo_column TYPE REF TO cl_salv_column.

    TRY.
        lo_column = io_columns->get_column( iv_column ).
        lo_column->set_short_text( iv_short ).
        lo_column->set_medium_text( iv_medium ).
        lo_column->set_long_text( iv_long ).
      CATCH cx_salv_not_found.
        RETURN.
    ENDTRY.

  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
*  Global data
*----------------------------------------------------------------------*
DATA: gt_result  TYPE tt_result,
      gt_package TYPE tt_selopt.

*----------------------------------------------------------------------*
*  Value help for the configuration field name
*----------------------------------------------------------------------*
AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_fld.

  DATA: lt_f4     TYPE STANDARD TABLE OF zabap_source_scan,
        lt_return TYPE STANDARD TABLE OF ddshretval,
        ls_return TYPE ddshretval.

  SELECT * FROM zabap_source_scan INTO TABLE lt_f4.
  IF sy-subrc = 0.
    SORT lt_f4 BY fieldname.
    DELETE ADJACENT DUPLICATES FROM lt_f4 COMPARING fieldname.

    CALL FUNCTION 'F4IF_INT_TABLE_VALUE_REQUEST'
      EXPORTING
        retfield        = 'FIELDNAME'
        dynpprog        = sy-repid
        dynpnr          = sy-dynnr
        dynprofield     = 'P_FLD'
        value_org       = 'S'
      TABLES
        value_tab       = lt_f4
        return_tab      = lt_return
      EXCEPTIONS
        parameter_error = 1
        no_values_found = 2
        OTHERS          = 3.

    IF sy-subrc = 0.
      READ TABLE lt_return INTO ls_return INDEX 1.
      IF sy-subrc = 0.
        p_fld = ls_return-fieldval.
      ENDIF.
    ENDIF.
  ENDIF.

*----------------------------------------------------------------------*
*  Validations
*----------------------------------------------------------------------*
AT SELECTION-SCREEN.

  IF p_std IS INITIAL.

    IF p_srch IS INITIAL AND p_fld IS INITIAL.
      MESSAGE 'Enter a search string or a field name' TYPE 'E'.
    ENDIF.

    IF p_prog IS INITIAL AND p_clas IS INITIAL AND p_fugr IS INITIAL.
      MESSAGE 'Select at least one object type to be scanned' TYPE 'E'.
    ENDIF.

    IF p_max < 0.
      MESSAGE 'Maximum number of hits must not be negative' TYPE 'E'.
    ENDIF.

  ENDIF.

*----------------------------------------------------------------------*
*  Main processing
*----------------------------------------------------------------------*
START-OF-SELECTION.

  DATA: lv_subrc   TYPE sysubrc,
        lv_message TYPE bapi_msg,
        lv_limit   TYPE xfeld,
        lv_msgtext TYPE string,
        lv_title   TYPE string,
        lv_count   TYPE i,
        lv_countc  TYPE c LENGTH 10,
        lv_report  TYPE trdir-name,
        lv_dummy   TYPE trdir-name.

  IF p_std = abap_true.

*   hand over to the standard ABAP Source Scan report. The program name
*   is passed dynamically so that this report also compiles on systems
*   where RS_ABAP_SOURCE_SCAN is not available.
    lv_report = gc_std_scan.
    SELECT SINGLE name FROM trdir INTO lv_dummy WHERE name = lv_report.
    IF sy-subrc = 0.
      SUBMIT (lv_report) VIA SELECTION-SCREEN AND RETURN.
    ELSE.
      MESSAGE 'Standard report RS_ABAP_SOURCE_SCAN is not available'
              TYPE 'S' DISPLAY LIKE 'E'.
    ENDIF.

  ELSE.

    CLEAR: gt_result, gt_package.

*   the package range is handed over as it was entered. When it is empty
*   the function module applies the default packages Z* and Y*.
    gt_package[] = s_devc[].

*   ---------------------------------------------------------------
*   the complete scan logic is executed by the RFC function module
*   ---------------------------------------------------------------
    CALL FUNCTION 'Z_ABAP_SOURCE_SCAN'
      EXPORTING
        iv_search_string  = p_srch
        iv_fieldname      = p_fld
        iv_scan_prog      = p_prog
        iv_scan_clas      = p_clas
        iv_scan_fugr      = p_fugr
        iv_case_sensitive = p_case
        iv_skip_comments  = p_comm
        iv_max_hits       = p_max
      IMPORTING
        ev_subrc          = lv_subrc
        ev_message        = lv_message
        ev_limit_reached  = lv_limit
      TABLES
        it_package        = gt_package
        et_result         = gt_result.

    IF lv_subrc <> 0.
      lv_msgtext = lv_message.
      IF lv_msgtext IS INITIAL.
        lv_msgtext = 'The source scan did not return any result'.
      ENDIF.
      MESSAGE lv_msgtext TYPE 'S' DISPLAY LIKE 'E'.
    ELSE.

      lv_count = lines( gt_result ).
      WRITE lv_count TO lv_countc LEFT-JUSTIFIED.
      CONCATENATE 'ABAP Source Scan -' lv_countc 'hit(s)'
             INTO lv_title SEPARATED BY space.

      IF lv_limit = abap_true.
        MESSAGE 'Maximum number of hits reached - result is incomplete'
                TYPE 'S'.
      ENDIF.

      lcl_alv=>display( EXPORTING iv_title  = lv_title
                        CHANGING  ct_result = gt_result ).
    ENDIF.

  ENDIF.
