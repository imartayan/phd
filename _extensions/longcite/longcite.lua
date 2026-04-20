if quarto.doc.is_format("pdf") then
  quarto.doc.include_text("in-header", [[
\DeclareCiteCommand{\longtextcite}
  {}
  {\printtext[bibhyperref]{%
    \printnames{labelname}\addspace(\printfield{year})}}
  {\multicitedelim}
  {}
]])
end

return {
  ['longcite'] = function(args, kwargs, meta)
    local key = pandoc.utils.stringify(args[1])
    if quarto.doc.is_format("pdf") then
      return pandoc.RawInline("latex", "\\longtextcite{" .. key .. "}")
    else
      local citation = pandoc.Citation(key, pandoc.NormalCitation)
      return pandoc.Cite({ pandoc.Str("") }, { citation })
    end
  end
}
