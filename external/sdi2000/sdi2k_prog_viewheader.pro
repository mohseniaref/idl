; >>>> begin comments
;==========================================================================================
;
; >>>> McObject Class: sdi2k_prog_viewheader
;
; This file contains the McObject method code for sdi2k_prog_viewheader objects:
;
; Mark Conde (Mc), Fairbanks, Septemebr 2000.
;
; >>>> end comments
; >>>> begin declarations
;         menu_name = View Header
;        class_name = sdi2k_prog_viewheader
;       description = SDI Program - View Header
;           purpose = SDI operation
;       idl_version = 5.2
;  operating_system = Windows NT4.0 terminal server 
;            author = Mark Conde
; >>>> end declarations


;==========================================================================================
; This is the (required) "new" method for this McObject:

pro sdi2k_prog_viewheader_new, instance, dynamic=dyn, creator=cmd
;---First, properties specific to this object:
    cmd = 'instance = {sdi2k_prog_viewheader, '
    cmd = cmd + 'wtitle: ''SDI Program - View Header'', '    
;---Now add fields common to all SDI objects. These will be grouped as sub-structures:
    sdi2k_common_fields, cmd, automation=automation, geometry=geometry
;---Next, add the required fields, whose specifications are read from the 'declarations'
;   section of the comments at the top of this file:
    cmd = cmd + 'update_divisor: 10, update_count: 0, '
    whoami, dir, file    
    obj_reqfields, dir+file, cmd, dynamic=dyn
;---Now, create the instance:
    status = execute(cmd)
end

;==========================================================================================
; This is the event handler for events generated by the sdi2k_prog_viewheader object:
pro sdi2k_prog_viewheader_event, event
    widget_control, event.top, get_uvalue=instance

;---Check for a new frame event sent by the control module:
    nm      = 0
    matched = where(tag_names(event) eq 'NAME', nm)
    if nm gt 0 then begin
       if event.(matched(0)) eq 'NewFrame' then begin
          instance.update_count = instance.update_count + 1
          if instance.update_count ge instance.update_divisor then begin
             instance.update_count = 0
             sdi2k_showheader
          endif
          widget_control, event.top, set_uvalue=instance
       end
       return
    endif

;---Get the menu name for this event:
    widget_control, event.id, get_uvalue=menu_item
    if n_elements(menu_item) eq 0 then menu_item = 'Nothing valid was selected'
   print, menu_item 
;---Handle other menu events:
    if (menu_item eq 'Exit') then sdi2k_viewheader_end

end

pro sdi2k_viewheader_end, dummy
@sdi2kinc.pro
    wid_pool, 'SDI program - View Header', widx, /get
    if not(widget_info(widx, /valid_id)) then return
    wid_pool, 'sdi2k_prog_header_', didx, /destroy
    wid_pool, 'SDI program - View Header', widx, /destroy
end

pro sdi2k_showheader
@sdi2kinc.pro

;---Get the widget identifier of the header widget, if it exists:    
    wid_pool, 'SDI Program - Header Display', hidx, /get
    wid_pool, 'SDI Program - Header None',    nidx, /get

;---Destroy any header display if disallowed by the host:
    if not(host.controller.behavior.show_header) then begin
       wid_pool, 'SDI Program - Header', didx, /destroy
       return
    endif
    
    tagz = indgen(n_tags(host.operation.header)-2)
    break_array = tagz
        
;---Just return if we have no file and a widget that reflects that:
    if host.operation.header.file_specifier eq 'None' and widget_info(nidx, /valid_id) then return 

;---Create the "No file" header widget:
    if host.operation.header.file_specifier eq 'None' then begin
       wid_pool, 'SDI Program - Header', didx, /destroy
       v_struk,  {file_specifier: host.operation.header.file_specifier}, widget_id=nidx, $
                  title='SDI Header'
       wid_pool, 'SDI Program - Header None', nidx, /add
    endif

;---If we have a file and a widget to display it, update the display:
    if host.operation.header.file_specifier ne 'None' and widget_info(hidx, /valid_id) then begin
       v_struk,  host.operation.header, widget_id=hidx, break_array=break_array, $
                  title='SDI Header'
       return 
    endif

;---If we have a file but no widget, go ahead and make one:
    if host.operation.header.file_specifier ne 'None' then begin
       wid_pool, 'SDI Program - Header', didx, /destroy
       v_struk,  host.operation.header, widget_id=hidx, tagz=tagz, break_array=break_array, $
                 title='SDI Header'
       wid_pool, 'SDI Program - Header Display', hidx, /add
    endif
end

;==========================================================================================
; This is the (required) "autorun" method for this McObject. If no autorun action is 
; needed, then this routine should simply exit with no action:

pro sdi2k_prog_viewheader_autorun, instance
@sdi2kinc.pro

    sdi2k_showheader
    wid_pool, 'sdi2k_prog_header_', hidx, /get
    hidx = hidx(0)
    if widget_info(hidx, /valid_id) then widget_control, hidx, set_uvalue=instance
end

;==========================================================================================
; This is the (required) class method for creating a new instance of the sdi2k_prog_viewheader object. It
; would normally be an empty procedure.  Nevertheless, it MUST be present, as the last procedure in 
; the methods file, and it MUST have the same name as the methods file.  By calling this
; procedure, the caller forces all preceeding routines in the methods file to be compiled, 
; and so become available for subsequent use:

pro sdi2k_prog_viewheader
end

