*"----------------------------------------------------------------------
*" Core logic of the ABAP source code scan.
*"
*" Call this function module from every development that needs a source
*" code scan - the logic must not be duplicated anywhere else.
*"
*"   IV_SEARCH_STRING supplied -> that string is scanned for.
*"   IV_SEARCH_STRING blank    -> IV_FIELDNAME is mandatory and every
*"                                EXISTING_VALUE maintained in
*"                                ZABAP_SOURCE_SCAN for that field name
*"                                is scanned for, one after the other.
*"   IT_PACKAGE empty          -> the scan is restricted to the default
*"                                packages Z* and Y*.
*"
*"   EV_SUBRC = 0  hits returned in ET_RESULT
*"   EV_SUBRC = 4  nothing found or input error, see EV_MESSAGE
*"
*" REPLACE_VALUE is returned for information only. This function module
*" never changes any source code.
*"----------------------------------------------------------------------

  DATA: lo_scan   TYPE REF TO lcl_source_scan,
        lt_devc   TYPE tt_scan_selopt,
        ls_devc   TYPE zsabap_scan_selopt,
        lt_result TYPE tt_scan_result,
        lv_failed TYPE xfeld,
        lv_msg    TYPE string.

  CLEAR: ev_subrc, ev_message, ev_limit_reached.
  REFRESH et_result.

  lt_devc[] = it_package[].

* default package restriction Z* and Y*
  IF lt_devc IS INITIAL.
    CLEAR ls_devc.
    ls_devc-sign   = 'I'.
    ls_devc-option = 'CP'.
    ls_devc-low    = 'Z*'.
    APPEND ls_devc TO lt_devc.
    ls_devc-low    = 'Y*'.
    APPEND ls_devc TO lt_devc.
  ENDIF.

  CREATE OBJECT lo_scan
    EXPORTING
      iv_search_string  = iv_search_string
      iv_fieldname      = iv_fieldname
      it_devclass       = lt_devc
      iv_scan_prog      = iv_scan_prog
      iv_scan_clas      = iv_scan_clas
      iv_scan_fugr      = iv_scan_fugr
      iv_case_sensitive = iv_case_sensitive
      iv_skip_comments  = iv_skip_comments
      iv_max_hits       = iv_max_hits.

  lo_scan->run( IMPORTING ev_failed  = lv_failed
                          ev_message = lv_msg ).

  ev_limit_reached = lo_scan->is_limit_reached( ).

  IF lv_failed = abap_true.
    ev_subrc   = 4.
    ev_message = lv_msg.
    RETURN.
  ENDIF.

  lt_result   = lo_scan->get_results( ).
  et_result[] = lt_result.
  ev_subrc    = 0.
