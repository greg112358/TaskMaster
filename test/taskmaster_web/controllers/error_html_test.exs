# async: false throughout — SQLite has a single writer, and with
# `transaction_mode: :immediate` every sandbox owner holds the write lock for
# the whole test, so two concurrent tests deadlock even when neither writes.
defmodule TaskmasterWeb.ErrorHTMLTest do
  use TaskmasterWeb.ConnCase, async: false

  # Bring render_to_string/4 for testing custom views
  import Phoenix.Template, only: [render_to_string: 4]

  test "renders 404.html" do
    assert render_to_string(TaskmasterWeb.ErrorHTML, "404", "html", []) == "Not Found"
  end

  test "renders 500.html" do
    assert render_to_string(TaskmasterWeb.ErrorHTML, "500", "html", []) == "Internal Server Error"
  end
end
