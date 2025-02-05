# pacman::p_load(shiny, tidyverse, shinydashboard, lubridate, scales)
library(shiny)
library(bslib)
library(ggplot2)
library(dplyr)
library(sf)


##TODO:
# (gg)Plot subpolygons with pointer displaying info about:
# - Area
# - Volume
# - Grams of down needed

# Cross section image

# Info panel with expected weight and total down, baffle material needed

# Final upper width is width of chamber roof + baffleLength + seam allowance
# Final lower is input dims + seam allowance

options(digits=2)

# Functions
#---------------------------
round_any = function(x, accuracy, f=round){f(x/ accuracy) * accuracy}
#---------------------------


# Frontend
#---------------------------
design_accordion <- bslib::accordion_panel(
  "Design",# icon = bsicons::bs_icon("menu-app"),
  numericInput('maxDim','Longest Dimension (cm)', 210, min = 0),
  numericInput('baffleHeight','Baffle Height (cm)', 2, min = 0),
  numericInput('chamberHeight','Max Chamber Height (cm)', 2.5, min = 0),
  numericInput('chamberWidth','Chamber Width (cm)', 15, min = 0),
  numericInput('percVertBaffle','% Length with Vertical Baffles', 100, min = 0, max = 100)
)

materials_accordion <- bslib::accordion_panel(
  "Materials",# icon = bsicons::bs_icon("sliders"),
  numericInput('FP','Fill Power', 750, min = 500, max = 1000, step = 50),
  numericInput('overstuff','% Overstuff', 10),
  numericInput('innerWeight','Inner Fabric Weight (gsm)', 50, min = 0),
  numericInput('outerWeight','Outer Fabric Weight (gsm)', 50, min = 0),
  numericInput('baffleWeight','Baffle Material Weight (gsm)', 25, min = 0),
  numericInput('seamAllowance','Seam Allowance (cm)', 1, min = 0, step = 0.25)
)

manual_entry_card <- bslib::card(
  bslib::card_body(
    bslib::layout_column_wrap(
      width = 1/2,
      # manual input
      shiny::numericInput('x_add','X', 0, min = 0),
      shiny::numericInput('y_add','Y', 0, min = 0)
    )
  )
)

plot_input_card <- bslib::card(
  bslib::card_header("Define vertices manually or click to draw right side of the quilt"),
    manual_entry_card, 
    bslib::card_body(fillable = T,
    # button to add vertices
    actionButton("add_point", "Add Point"),
    
    ),
    verbatimTextOutput("hover_info"),
    plotOutput("input_plot",
              height = 600,
            #add plot click functionality
              click = "plot_click",
            #add the hover options
              hover = hoverOpts(
                id = "plot_hover",
                nullOutside = TRUE)
              ),
    # button to remove last vertex
    actionButton("rem_point", "Remove Last Point"),
    actionButton("rem_all_points", "Clear")
)

selected_points_card <- bslib::card(
  bslib::card_header("Selected Points"),
  tableOutput("table")
)

card2 <- bslib::card(
  bslib::card_header("Text Output"),
  verbatimTextOutput("test")
)

card3 <- bslib::card(
  bslib::card_header("Test Output"),
  verbatimTextOutput("cross_section_plot_df")
)


cross_section_card <- bslib::card(
  bslib::card_header("Cross Sectional View"),
  plotOutput("cross_section_plot")
)

area_card <- bslib::card(
  bslib::card_header("Aerial View"),
  plotOutput("area_plot")
)

plot_input_card <- bslib::card(
  bslib::card_header("Define vertices manually or click to draw right side of the quilt"),
    manual_entry_card, 
    bslib::card_body(fillable = T,
    # button to add vertices
    actionButton("add_point", "Add Point"),
    
    ),
    verbatimTextOutput("hover_info"),
    plotOutput("input_plot",
              height = 600,
            #add plot click functionality
              click = "plot_click",
            #add the hover options
              hover = hoverOpts(
                id = "plot_hover",
                nullOutside = TRUE)
              ),
    # button to remove last vertex
    actionButton("rem_point", "Remove Last Point"),
    actionButton("rem_all_points", "Clear")
)

# UI layout
ui <- bslib::page_navbar(
  title = "Down Quilt Designer",
  theme = bslib::bs_theme(version=5, bootswatch = "sketchy"), # Can specify base_font and code_font
  sidebar = bslib::sidebar(
    bslib::accordion(
      design_accordion,
      materials_accordion
  )
),
bslib::nav_panel(
  title = "Dimensions",
  bslib::layout_column_wrap(
    width = NULL,
    height = NULL,
    fill = FALSE,
    style = bslib::css(grid_template_columns = "2fr 1fr"),
    plot_input_card, 
    selected_points_card)
  ),
bslib::nav_panel(
  title = "Output",
  bslib::layout_column_wrap(
                  width = 1/2,
                  height = 300,
                  area_card,
                  card2,
                cross_section_card,
                card3
              )
                )

)
#---------------------------


# Backend
#---------------------------
server = function(input, output){
  
  # set up reactive dataframe with example data
  values <- shiny::reactiveValues()
  values$user_input <- data.frame(x = c(0, 71, 71, 50, 0),
                                  y = c(210, 210, 100, 0, 0))
  
all_selected_points_x <- shiny::reactive({
  req(values$user_input)
  c(values$user_input$x, -rev(values$user_input$x))
})

all_selected_points_y <- shiny::reactive({
  req(values$user_input)
  c(values$user_input$y, rev(values$user_input$y))
})
  
#reactive expression to calculate subpolygons
polygon_df <- shiny::reactive({
  req(all_selected_points_x)
  req(all_selected_points_y)
  req(input$chamberWidth)
  req(input$baffleHeight)

  #create polygon from selected points
  poly <- sf::st_polygon(list(cbind(all_selected_points_x(), all_selected_points_y())))
  #create bounding boxes that are chamberWidth apart until greatest width
  bbox <- st_bbox(poly)
  # Create vertical lines spaced chamberWidth apart
  x_seq <- seq(0, (bbox["xmax"] + input$chamberWidth), by = input$chamberWidth)
  lines <- lapply(x_seq, function(x) {
    st_linestring(rbind(c(x, bbox["ymin"]), c(x, bbox["ymax"])))
  })
  # Combine lines into a multi-line geometry
  multiline <- st_sfc(lines, crs = st_crs(polygon))
  bboxes <- list()
  for (i in 1:(length(multiline)-1))
    {
    current_line <- multiline[i]
    next_line <- multiline[i+1]

    bbox_section <- st_polygon(list(rbind(
      st_coordinates(current_line)[1:2,1:2],
      st_coordinates(next_line)[2:1,1:2],
      st_coordinates(current_line)[1,1:2]
    )))

    bboxes[i] <- bbox_section
  }
  #use intersection to find input polygon values within each bounding box
  subpolys <- list()
  # area <- list()
  id = list()
  for (i in 1:length(bboxes))
  {
    intersect <- st_intersection(poly, st_polygon(bboxes[i]))
    subpolys[i] <- st_segmentize(intersect, 1)
    # area[i] <- st_area(intersect)
    id[i] <- i
  }
  subpolys <- lapply(subpolys, as.data.frame)
  for (i in 1:length(subpolys))
    {
      names(subpolys[[i]]) <- c('x','y')
      subpolys[[i]]['ID'] <- id[i]
      # subpolys[[i]]['segmentWidth'] <- subpolys[[i]]['x'] - min(subpolys[[i]]['x'])
      # subpolys[[i]]['Area'] <- area[i]
    # Placehold volume calc. Needs to factor in max baffle height
      # subpolys[[i]]['Volume'] <- as.numeric(area[i]) * as.numeric(input$baffleHeight)
      
  }
  polygon_df <- do.call(rbind, subpolys)
  polygon_df
})


#reactive expression to calculate subpolygons
cross_section_df <- shiny::reactive({
  req(polygon_df)
  req(input$chamberHeight)
  req(input$baffleHeight)

  # subset to only single observation per y unit per group
  # This retains one chamberWidth value per y allowing for calculation of area of each slice and thus diff cut calculations.
  cross_section_df <- polygon_df() %>%
    group_by(ID) %>%
    mutate(segmentWidth = x - min(x)) %>%
    distinct(y, .keep_all = T) %>%
    filter(segmentWidth > 0) %>%
    as.data.frame(.)

  # Define the parameters for the ellipse
  a <- cross_section_df$segmentWidth / 2  # Semi-major axis (half of width)
  b <- input$chamberHeight - input$baffleHeight # Semi-minor axis (half of height)
  # Calculate perimeter of ellipse
  h <- ((a-b)/(a+b))^2
  p <- pi * (a + b) * (1 + 3 * h / (10 + sqrt((4 - 3 * h))))
  # Calculate length of chamber roof (half perimeter)
  cross_section_df$chamberRoofLength <- p / 2
  # Calculate half ellipse area
  cross_section_df$chamberUpperArea <- (pi * a * b) / 2
  # Calculate lower chamber area
  cross_section_df$chamberLowerArea <- cross_section_df$segmentWidth * input$baffleHeight
  # Area of each slice (defined by st_segmentize as 1cm)
  cross_section_df$sliceArea <- cross_section_df$chamberUpperArea + cross_section_df$chamberLowerArea

  cross_section_df
  })

  cross_section_plot_df <- shiny::reactive({
    req(cross_section_df)
    req(input$chamberHeight)
    req(input$baffleHeight)

    cross_section_plot_df <- 
      cross_section_df() %>%
      group_by(ID) %>%
      filter(y == max(y))

    a <- cross_section_plot_df$segmentWidth / 2
    b <- input$chamberHeight - input$baffleHeight # Semi-minor axis (half of height)

    # Create a sequence of t values from 0 to 2*pi
    t <- seq(0, 2 * pi, length.out = 100)

    # Parametric equations for the ellipse
    x_coords <- a * cos(t) + c$a
    y_coords <- b * sin(t) + input$baffleHeight

    # # Combine the x and y coordinates into a matrix and close the curve
    # coords <- cbind(x_coords[1:length(t)/2], y_coords[1:length(t)/2])
    # coords <- rbind(coords, c(0, 0), c(input$chamberWidth, 0), coords[1,])  # Closing the curve

    # # Step 2: Create the sf object for the polygon
    # ellipse_polygon <- st_sfc(st_polygon(list(coords)))

    # # Step 3: Create an sf data frame
    # ellipse_sf <- st_sf(geometry = ellipse_polygon)

    # ellipse_sf


    # cross_section_plot_df <- 
    #   cross_section_df() %>%
    #   group_by(ID) %>%
    #   filter(y = max(y))

    # cross_section_plot_df()
    cross_section_plot_df
  })
  
  
  # create design plot
  output$input_plot <- shiny::renderPlot({
    ggplot(values$user_input, aes(x = x, y = y)) +
      geom_vline(xintercept = 0, linetype = "dotted", linewidth = 2) +
      geom_point(aes()) +
      geom_path(linewidth = 1.5) +
      lims(x = c(0, input$maxDim), y = c(0, input$maxDim)) +
      theme(legend.position = "bottom") +
      coord_fixed()
  })
  
  # add new row to reactive dataframe upon clicking plot
  shiny::observeEvent(input$plot_click, {
    add_row <- data.frame(x = round_any(input$plot_click$x, 0.5),
                          y = round_any(input$plot_click$y, 0.5))
    # add row to the data.frame
    values$user_input <- rbind(values$user_input[1:nrow(values$user_input)-1,], add_row, values$user_input[nrow(values$user_input),])
  })

  # add row on actionButton click
  shiny::observeEvent(input$add_point, {
    add_row <- rbind(values$user_input, c(input$x_add, input$y_add))
    values$user_input <- add_row
  })
  
  # remove row on actionButton click
  shiny::observeEvent(input$rem_point, {
    rem_row <- values$user_input[-nrow(values$user_input), ]
    values$user_input <- rem_row
  })

  # clear all selected points on actionButton click
    shiny::observeEvent(input$rem_all_points, {
      values$user_input <- data.frame(x=double(),
                              y=double()
    )
    })
  
  
  # render a table of the dataframe
  output$table <- shiny::renderTable({
    values$user_input
    ## Test
    # all_selected_points()
  })
  
  output$hover_info <- shiny::renderPrint({
      hover=input$plot_hover
      cat("X value:", formatC(round_any(hover$x, 0.5), digits = 1, format = "f"), "\n")
      cat("Y value:", formatC(round_any(hover$y, 0.5  ), digits = 1, format = "f"))
  })

  output$area_plot <- shiny::renderPlot({
    req(polygon_df)

    ggplot() +
      geom_path(data = polygon_df(), aes(x = x, y = y, group = ID)) +
      theme(legend.position = "bottom")
  })

  output$cross_section_plot <- shiny::renderPlot({
    # Step 4: Plot the ellipse with ggplot2
    ggplot(data = cross_section_df()) +
      geom_sf(fill = "lightblue", color = "black") +
      ggtitle("Chamber Cross-section") +
      theme_minimal() 
  })

  output$cross_section_plot_df <- shiny::renderPrint({
    cross_section_plot_df()
  })

  output$test <- shiny::renderPrint({
    cross_section_df()
  })

}
#---------------------------

# Run app
shiny::shinyApp(ui, server)