module RedAppHelper

  def autosave_fld(record, fld_name, hash={})
    hash = hash.clone
    tag = "span" || hash.delete(:tag)
    blder = SDGUtils::HTML::TagBuilder.new(tag)
    blder
      .body(record.read_field(fld_name))
      .attr("data-record-cls", record.class.name)
      .attr("data-record-id", record.id)
      .attr("data-field-name", fld_name)
      .attr("contenteditable", true)
      .attr("class", "red-autosave")
      .attrs(hash)
      .build()
  end

end
