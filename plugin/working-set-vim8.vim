if v:version >= 800 || has('nvim')

if executable('socat') != 1
  echomsg "Warning: working-set requires the `socat` command to be installed and in $PATH"
endif

let g:WorkingSetSocketPath   = get(g:, 'WorkingSetSocketPath', '.working_set_socket')

" Connection Management
" =====================

func! s:EnsureConnection()
  if has("nvim")
    if exists("g:WSchannel") && g:WSchannel != 0
      " Nvim Connected, do nothing.
    else
      call s:Connect(g:WorkingSetSocketPath)
    endif
  else
    if exists("g:WSchannel") && ch_status(g:WSchannel) == 'open'
      " Vim Connected, do nothing.
    else
      call s:Connect(g:WorkingSetSocketPath)
    endif
  endif
endfunc

if has('nvim')
  func! s:Connect(socketfile)
      let g:WSjob = jobstart("socat - UNIX-CONNECT:" . a:socketfile, {
            \ "on_stdout": function("s:InputHandler"),
            \ "on_stderr": function("s:ErrorHandler"),
            \ "on_exit":   function("s:ExitHandler")
            \ })

      let g:WSchannel = g:WSjob
  endfunc

else
  func! s:Connect(socketfile)
    let g:WSjob = job_start("socat - UNIX-CONNECT:" . a:socketfile, { "err_cb": function("s:ErrorHandler"), "out_cb": function("s:InputHandler") })
    let g:WSchannel = job_getchannel(g:WSjob)

    if ch_status(g:WSchannel) != "open"
      echomsg "Unable to connect to .working_set_socket"
    endif
  endfunc
endif

func! s:InputHandler(job_id, response_body, ...)
  if has('nvim')
    let body = join(a:response_body, "")
  else
    let body = a:response_body
  endif
  if body == ""
    " This happens when the WSjob exits
    return
  endif
  let payload = json_decode(body)
  if payload.message == "selected_item"
    call s:SyncLocation(payload)
  elseif payload.message == "selected_item_content"
    call s:HandleGrabbedItem(payload)
  endif
endfunc

func! s:ErrorHandler(job_id, msg, ...)
  if has('nvim')
    let msg = join(a:msg, "")
  else
    let msg = a:msg
  endif
  echomsg "WS Error: " . msg
endfunc

func! s:ExitHandler(...)
  echomsg "Working Set lost connection..."
  let g:WSchannel = 0
endfunc

" Low Level API Functions
" =======================

func! s:SyncLocation(location)
  if has_key(a:location, "file_path")
    exe 'e' a:location.file_path
  endif
  if has_key(a:location, "row")
    exe 'norm!' a:location.row . 'gg'
  endif
  if has_key(a:location, "column")
    exe 'norm!' a:location.column . '|'
  endif
endfunc

func! s:SendMsg(msg, ...)
  let payload = { 'message': a:msg }
  let options = {}
  if exists("a:1")
    call extend(payload, a:1)
  endif
  if exists("a:2")
    if has_key(a:2, "callback")
      let options.callback = function(a:2.callback, a:2.args)
    endif
  endif
  call s:EnsureConnection()
  call s:SendMsgRaw(json_encode(payload). "\n")
endfunc

func! s:SendMsgRaw(msg)
  if has('nvim')
    call chansend(g:WSchannel, a:msg)
  else
    call ch_sendraw(g:WSchannel, a:msg)
  endif
endfunc

" Medium Level API Functions
" ==========================

func! s:Sync()
  call s:SendMsg("tell_selected_item")
endfunc

func! s:SelectNextItem()
  call s:SendMsg("select_next_item")
  call s:Sync()
endfunc

func! s:SelectPrevItem()
  call s:SendMsg("select_prev_item")
  call s:Sync()
endfunc

" High Level API Functions
" ========================

func! s:SearchWithOptions(term, options)
  echomsg "WS Search: " . json_encode(a:options) . " " . a:term
  call s:SendMsg("search_changed", { 'args': a:term, 'options': a:options })
endfunc

func! s:SearchCurrentWord()
  let wordUnderCursor = expand("<cword>")
  call s:SearchWithOptions(wordUnderCursor, { 'whole_word': v:true })
endfunc

func! s:Grab(pasteCmd)
  let g:WSNextPasteCmd = a:pasteCmd
  call s:SendMsg("tell_selected_item_content")
endfunc

func! s:HandleGrabbedItem(payload)
  let line = substitute(a:payload.data, '^\s*', '', '')
  call setreg('"', line, 'l')
  exe 'normal ""' . g:WSNextPasteCmd
endfunc

command! WSSelectNextItem call s:SelectNextItem()
command! WSSelectNextItem call s:SelectNextItem()

" Command mappings
" ================

command! -nargs=1 WS call s:SearchWithOptions(<f-args>, {})
command! -nargs=1 WSw call s:SearchWithOptions(<f-args>, { 'whole_word': v:true })
command! WSSync call s:Sync()
command! -nargs=1 WSGrab call s:Grab(<f-args>)
command! WSSelectNextItem call s:SelectNextItem()
command! WSSelectPrevItem call s:SelectPrevItem()
command! WSSearchCurrentWord call s:SearchCurrentWord()

if !exists('g:WorkingSetSkipMappings')
  nnoremap <silent> <C-n>     :WSSelectNextItem<CR>
  nnoremap <silent> <C-p>     :WSSelectPrevItem<CR>
  nnoremap <silent> <Leader>* *N:WSSearchCurrentWord<CR>
  nnoremap <silent> <Leader>p :WSGrab p<CR>
  nnoremap <silent> <Leader>P :WSGrab P<CR>
endif

endif

