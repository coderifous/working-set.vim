if v:version >= 800

let g:WorkingSetSocketPath   = get(g:, 'WorkingSetSocketPath', '.working_set_socket')

" Connection Management
" =====================

func! s:EnsureConnection()
  if exists("g:WSchannel") && ch_status(g:WSchannel) == "open"
    " Connected, do nothing.
  else
    call s:Connect(g:WorkingSetSocketPath)
  endif
endfunc

func! s:Connect(socketfile)
  if exists("g:WSjob") && job_status(g:WSjob) == "run"
    call job_stop(g:WSjob)
  endif

  let g:WSjob = job_start("socat - UNIX-CONNECT:" . a:socketfile, { "err_cb": function("s:ErrorHandler"), "out_cb": function("s:InputHandler") })
  let g:WSchannel = job_getchannel(g:WSjob)

  if ch_status(g:WSchannel) != "open"
    echomsg "Unable to connect to .working_set_socket"
  endif
endfunc

func! s:InputHandler(channel, response_body)
  let payload = json_decode(a:response_body)
  if payload.message == "selected_item"
    call s:SyncLocation(payload)
  endif
endfunc

func! s:ErrorHandler(channel, msg)
  echomsg "WS Error: " . a:msg
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
  let payload = #{ message: a:msg }
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
  call ch_sendraw(g:WSchannel, json_encode(payload) . "\n", options)
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
  call s:SendMsg("search_changed", #{ args: a:term, options: a:options })
endfunc

func! s:SearchCurrentWord()
  let wordUnderCursor = expand("<cword>")
  call s:SearchWithOptions(wordUnderCursor, #{ whole_word: v:true })
endfunc

func! s:Grab(pasteCmd)
  call s:SendMsg("tell_selected_item_content", {}, #{ callback: "s:HandleGrabbedItem", args: [a:pasteCmd] })
endfunc

func! s:HandleGrabbedItem(pasteCmd, channel, msg)
  let line = substitute(a:msg, '^\s*', '', '')
  call setreg('"', line, 'l')
  exe 'normal ""' . a:pasteCmd
endfunc

command! WSSelectNextItem call s:SelectNextItem()
command! WSSelectNextItem call s:SelectNextItem()

" Command mappings
" ================

command! -nargs=1 WS call s:SearchWithOptions(<f-args>, {})
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

