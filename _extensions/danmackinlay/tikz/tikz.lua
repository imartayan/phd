--[[
tikz.lua - A Lua filter to process TikZ code blocks and generate figures.

Based on the style of 'quarto_diagram/diagram.lua', adapted for TikZ diagrams.
]]

PANDOC_VERSION:must_be_at_least '3.0'

local pandoc                   = require 'pandoc'
local system                   = require 'pandoc.system'
local utils                    = require 'pandoc.utils'

local stringify                = utils.stringify
local with_temporary_directory = system.with_temporary_directory
local with_working_directory   = system.with_working_directory

local function read_file(filepath)
  local fh = io.open(filepath, 'rb')
  if not fh then return nil end
  local contents = fh:read('a')
  fh:close()
  return contents
end

local function write_file(filepath, content)
  local fh = io.open(filepath, 'wb')
  if not fh then return false end
  fh:write(content)
  fh:close()
  return true
end

-- ── Cache ─────────────────────────────────────────────────────────────────────

local image_cache = nil -- absolute path to cache directory, or nil when disabled

local function cache_default_dir()
  local cache_home = os.getenv 'XDG_CACHE_HOME'
  if not cache_home or cache_home == '' then
    local user_home = system.os == 'windows'
        and os.getenv 'USERPROFILE'
        or os.getenv 'HOME'
    if not user_home or user_home == '' then return nil end
    cache_home = pandoc.path.join { user_home, '.cache' }
  end
  local dir = pandoc.path.join { cache_home, 'tikz-diagram-filter' }
  pandoc.system.make_directory(dir, true)
  return dir
end

local function cache_entry_path(hash, options)
  if not image_cache then return nil end
  local key = pandoc.sha1(hash .. stringify(options))
  return pandoc.path.join { image_cache, key .. '.svg' }
end

local function get_cached_image(hash, options)
  local path = cache_entry_path(hash, options)
  return path and read_file(path)
end

local function cache_image(hash, options, imgdata)
  local path = cache_entry_path(hash, options)
  if path then write_file(path, imgdata) end
end

-- Initialises image_cache from tikz metadata; returns true when cache is active.
local function init_cache(tikz_conf)
  if tikz_conf.cache ~= true then
    image_cache = nil
    return false
  end
  image_cache = tikz_conf['cache-dir']
      and stringify(tikz_conf['cache-dir'])
      or cache_default_dir()
  if image_cache then
    pandoc.system.make_directory(image_cache, true)
  end
  return image_cache ~= nil
end

-- ── Utilities ─────────────────────────────────────────────────────────────────

local function check_dependency(cmd)
  local handle = io.popen("command -v " .. cmd .. " 2>/dev/null")
  if not handle then return false end
  local result = handle:read("*a")
  handle:close()
  return result ~= ""
end

local function properties_from_code(code, comment_start)
  local props = {}
  local pattern = comment_start:gsub('%p', '%%%1') .. '| ?' ..
      '([-_%w]+): ([^\n]*)\n'
  for key, value in code:gmatch(pattern) do
    if key == 'fig-attr' then
      local attr_value = ''
      local subpattern = comment_start:gsub('%p', '%%%1') .. '|   ([^\n]+)\n'
      for subvalue in code:gmatch(subpattern) do
        attr_value = attr_value .. subvalue .. '\n'
      end
      local parsed = pandoc.read(attr_value, 'yaml').blocks
      if #parsed > 0 then
        props[key] = pandoc.utils.block_to_lua(parsed[1])
      end
    else
      props[key] = value
    end
  end
  return props
end

local function diagram_options(cb)
  local attribs = properties_from_code(cb.text, '%%')
  for key, value in pairs(cb.attributes) do
    attribs[key] = value
  end

  local alt
  local caption
  local fig_attr = attribs['fig-attr'] or { id = cb.identifier }
  local filename
  local image_attr = {}
  local user_opt = {}

  for attr_name, value in pairs(attribs) do
    if attr_name == 'alt' then
      alt = value
    elseif attr_name == 'caption' then
      caption = pandoc.read(value, 'markdown').blocks
    elseif attr_name == 'filename' then
      filename = value
    elseif attr_name == 'additionalPackages' then
      user_opt['additional-packages'] = value
    elseif attr_name == 'header-includes' then
      user_opt['header-includes'] = value
    elseif attr_name == 'label' then
      fig_attr.id = value
    elseif attr_name == 'name' then
      fig_attr.name = value
    elseif attr_name ~= 'fig-attr' then
      local prefix, key = attr_name:match '^(%a+)%-(%a[-%w]*)$'
      if prefix == 'fig' then
        fig_attr[key] = value
      elseif prefix == 'image' or prefix == 'img' then
        image_attr[key] = value
      elseif prefix == 'opt' then
        user_opt[key] = value
      else
        image_attr[attr_name] = value
      end
    end
  end

  return {
    ['alt'] = alt or {},
    ['caption'] = caption,
    ['fig-attr'] = fig_attr,
    ['filename'] = filename,
    ['image-attr'] = image_attr,
    ['opt'] = user_opt,
  }
end

-- ── Compilation ───────────────────────────────────────────────────────────────

local function compile_tikz_to_svg(code, user_opts, conf, basename)
  if not check_dependency('latex') then
    error("latex not found. Please install LaTeX to compile TikZ diagrams.")
  end
  if not check_dependency('dvisvgm') then
    error("dvisvgm not found. Please install dvisvgm (included in TeX Live) to convert DVI to SVG.")
  end

  local function process_in_dir(dir)
    return with_working_directory(dir, function()
      local base_filename = basename or "tikz-image"
      local tikz_file     = base_filename .. ".tex"
      local dvi_file      = base_filename .. ".dvi"
      local svg_file      = base_filename .. ".svg"

      local tikz_template = pandoc.template.compile [[
\documentclass[dvisvgm,tikz]{standalone}
$additional-packages$
$for(header-includes)$
$it$
$endfor$
\begin{document}
$body$
\end{document}
      ]]
      local meta          = {
        ['header-includes'] = { pandoc.RawInline(
          'latex',
          stringify(user_opts['header-includes'] or '')
        ) },
        ['additional-packages'] = { pandoc.RawInline(
          'latex',
          stringify(user_opts['additional-packages'] or '')
        ) },
      }
      local tex_code      = pandoc.write(
        pandoc.Pandoc({ pandoc.RawBlock('latex', code) }, meta),
        'latex',
        { template = tikz_template }
      )
      write_file(tikz_file, tex_code)

      -- DVI mode: no Ghostscript dependency for dvisvgm
      local ok, latex_err = pcall(
        pandoc.pipe, 'latex', { '-interaction=nonstopmode', tikz_file }, ''
      )
      if not ok then
        local log_content = read_file(base_filename .. ".log") or ""
        error("Error compiling TikZ figure '" .. base_filename .. "':\n" ..
          tostring(latex_err) .. "\nLaTeX Log:\n" .. log_content ..
          "\nTikZ Code:\n" .. code)
      end

      local args = { '--no-fonts', '--output=' .. svg_file }
      if user_opts['zoom'] then
        table.insert(args, '--zoom=' .. user_opts['zoom'])
      end
      table.insert(args, dvi_file)
      local ok_svg, svg_err = pcall(pandoc.pipe, 'dvisvgm', args, '')
      if not ok_svg then
        error("Error converting DVI to SVG for TikZ figure '" .. base_filename .. "':\n" ..
          tostring(svg_err) .. "\nTikZ Code:\n" .. code)
      end

      local imgdata = read_file(svg_file)
      if not imgdata then
        error("Failed to read generated SVG file for TikZ figure '" .. base_filename ..
          "'.\nTikZ Code:\n" .. code)
      end
      return imgdata
    end)
  end

  if conf.save_tex then
    local subdir = pandoc.path.join { conf.tex_dir, basename or pandoc.sha1(code) }
    pandoc.system.make_directory(subdir, true)
    return process_in_dir(subdir)
  else
    return with_temporary_directory("tikz", function(tmpdir)
      return process_in_dir(tmpdir)
    end)
  end
end

-- ── Filter ────────────────────────────────────────────────────────────────────

local function code_to_figure(conf)
  return function(block)
    if block.t ~= 'CodeBlock' then return nil end
    if not block.classes:includes('tikz') then return nil end

    -- For LaTeX output, embed tikz code directly instead of pre-rendering to SVG
    if quarto.doc.is_format('latex') then
      local code = block.text:gsub('%%%%[^\n]*\n', '')
      return pandoc.RawBlock('latex', code)
    end

    local dgr_opt  = diagram_options(block)
    local basename = dgr_opt.filename or pandoc.sha1(block.text)
    local fname    = basename .. '.svg'

    -- Try cache first, then compile, then fall back to an existing on-disk file.
    local imgdata = conf.cache and get_cached_image(block.text, dgr_opt.opt)

    if not imgdata then
      local ok, result = pcall(compile_tikz_to_svg, block.text, dgr_opt.opt, conf, basename)
      if ok and result then
        imgdata = result
        cache_image(block.text, dgr_opt.opt, imgdata)
      else
        -- Fall back to a previously compiled SVG in the source tree so that a
        -- local render without the LaTeX toolchain can still succeed.
        imgdata = read_file(conf.source_dir .. '/' .. fname)
        if imgdata then
          quarto.log.warning("TikZ figure '" .. basename .. "': using existing file (compilation unavailable)")
        else
          error("Error compiling TikZ figure '" .. basename .. "': " .. tostring(result))
        end
      end
    end

    -- Write to the book output directory so the rendered HTML can load the file.
    pandoc.system.make_directory(conf.write_dir, true)
    write_file(conf.write_dir .. '/' .. fname, imgdata)

    local img_path = conf.img_path_prefix .. fname
    local image = pandoc.Image(dgr_opt.alt, img_path, "", dgr_opt['image-attr'])

    return dgr_opt.caption and
        pandoc.Figure(pandoc.Plain { image }, dgr_opt.caption, dgr_opt['fig-attr']) or
        pandoc.Plain { image }
  end
end

local function configure(meta)
  local conf         = meta.tikz or {}
  meta.tikz          = nil -- prevent further processing of tikz metadata

  local cache_active = init_cache(conf)

  local save_tex     = conf['save-tex'] or false
  local tex_dir      = nil
  if save_tex then
    if cache_active then
      quarto.log.warning("Both 'cache' and 'save-tex' are enabled. Disabling 'save-tex' since caching is active.")
      save_tex = false
    else
      tex_dir = stringify(conf['tex-dir'] or 'tikz-tex')
      pandoc.system.make_directory(tex_dir, true)
    end
  end

  local rel_output_dir = conf['output-dir']
      and stringify(conf['output-dir'])
      or 'tikz-output'
  local project_dir = os.getenv('QUARTO_PROJECT_DIR') or ''
  -- QUARTO_DOCUMENT_PATH is the chapter *directory* (confirmed by inspection).
  local doc_dir = os.getenv('QUARTO_DOCUMENT_PATH') or system.get_working_directory()

  -- Quarto may pass output-dir as chapter-relative (e.g. "../fig/tikz") even though
  -- _quarto.yml specifies it project-relative ("fig/tikz").
  -- Strip any leading "../" to recover the project-relative form.
  -- NOTE: pandoc.path.normalize does NOT resolve ".." on all platforms, so we
  -- must strip manually rather than relying on normalise(doc_dir + rel_output_dir).
  local proj_rel_output_dir = rel_output_dir
  while proj_rel_output_dir:match('^%.%./') do
    proj_rel_output_dir = proj_rel_output_dir:sub(4)
  end

  local source_dir
  if pandoc.path.is_absolute(rel_output_dir) then
    source_dir = rel_output_dir
  elseif project_dir ~= '' then
    source_dir = pandoc.path.join { project_dir, proj_rel_output_dir }
  else
    source_dir = proj_rel_output_dir
  end

  -- depth: directory levels from the chapter source dir to the project root.
  local chapter_rel = project_dir ~= '' and doc_dir:sub(#project_dir + 2) or ''
  local depth = 0
  for _ in chapter_rel:gmatch('[^/\\]+') do depth = depth + 1 end
  local img_path_prefix = string.rep('../', depth) .. proj_rel_output_dir .. '/'

  -- write_dir: where SVGs must land so the rendered HTML can load them.
  -- Walk up `depth` levels from the HTML output file's directory to reach _book,
  -- then append the project-relative output dir.
  -- Falls back to source_dir when quarto.doc.output_file is unavailable.
  local write_dir = source_dir
  local output_file = quarto.doc.output_file
  if output_file then
    local html_dir = pandoc.path.directory(output_file)
    local book_root = html_dir
    for _ = 1, depth do
      book_root = pandoc.path.directory(book_root)
    end
    write_dir = pandoc.path.join { book_root, proj_rel_output_dir }
  end

  return {
    cache           = cache_active,
    save_tex        = save_tex,
    tex_dir         = tex_dir,
    source_dir      = source_dir,
    write_dir       = write_dir,
    img_path_prefix = img_path_prefix,
  }
end

return {
  {
    Pandoc = function(doc)
      local conf = configure(doc.meta)
      return doc:walk {
        CodeBlock = code_to_figure(conf),
      }
    end
  }
}
