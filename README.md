# R-ML Images

These images contain common ML packages used in R. They are built on top of [Rocker](https://rocker-project.org/) images, in particular the [geospatial](https://rocker-project.org/images/versioned/rstudio.html) image, meaning they come with RStudio, teh tidyverse, TeX Live and GDAL already installed. On top of that we added various ML packages as well as additional packages for geospatial, forecasting, optimization, workflows and other quality of life and data manipulation packages.

The image is designed to be used either as a dev container inside VS Code or in GitHub Spaces, or standalone via the RStudio interface.

# Usage

```sh
docker pull jaredlander/r-ml:cpu-4.4.1

```