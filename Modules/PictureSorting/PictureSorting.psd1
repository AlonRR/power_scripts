@{
    RootModule        = 'PictureSorting.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'b3f5c1a2-6d4e-4a7b-9c8d-0e1f2a3b4c5d'
    Author            = 'AlonRR'
    Description       = 'Organizes photos and videos into year/month folders by EXIF date taken or last write time.'
    PowerShellVersion = '7.0'

    # Only the public command and its aliases are exposed; all helpers are private.
    FunctionsToExport = @('Move-PicturesByDate')
    AliasesToExport   = @('Sort-Pictures', 'Sort_Pictures_By_Date_Taken')
    CmdletsToExport   = @()
    VariablesToExport = @()
}
