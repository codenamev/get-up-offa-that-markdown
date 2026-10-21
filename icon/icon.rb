# The app icon: the Markdown mark (M and a down arrow) on a funky orange tile, drawn on
# macOS's icon grid (an 824 px tile, 100 in from each edge). See README for the export.
Shoes.app(title: "Get Up Offa That Markdown icon", width: 1024, height: 1024, resizable: false) do
  background white
  nostroke
  fill "#f59f00".."#d9480f"
  rect 100, 100, 824, 824, 185

  # the mark's rounded frame
  fill white
  rect 190, 300, 644, 424, 70
  fill "#e8590c"
  rect 222, 332, 580, 360, 44

  # M
  fill white
  shape do
    move_to 290, 620
    line_to 290, 400
    line_to 360, 400
    line_to 430, 490
    line_to 500, 400
    line_to 570, 400
    line_to 570, 620
    line_to 505, 620
    line_to 505, 500
    line_to 430, 590
    line_to 355, 500
    line_to 355, 620
    line_to 290, 620
  end

  # down arrow
  shape do
    move_to 650, 400
    line_to 715, 400
    line_to 715, 520
    line_to 765, 520
    line_to 682, 620
    line_to 600, 520
    line_to 650, 520
    line_to 650, 400
  end
end
