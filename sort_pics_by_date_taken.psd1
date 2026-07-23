@{
    RootModule        = 'sort_pics_by_date_taken.psm1'
    ModuleVersion     = '0.0.1'
    Description       = 'Module to organize pictures into folders by date taken'
    PowerShellVersion = '5.1'
    FunctionsToExport = 'Move-PicturesByDate'
    AliasesToExport   = @('Sort-Pictures', 'Sort_Pictures_By_Date_Taken')
    RequiredModules   = @('.\Modules\PictureSorting\PictureSorting.psd1')
}

