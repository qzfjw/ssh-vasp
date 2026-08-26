@{
    SchemaVersion = 1

    GammaPolicy = @{
        PreferGammaCentered = $true
        Reason = 'Routine meshes should include the Gamma point whenever possible.'
    }

    MeshProfiles = @{
        GammaLengthProduct25 = @{
            Description = 'Routine relaxation/static mesh. Each mesh component times the corresponding lattice length should be at least 25 Angstrom.'
            Style = 'Gamma'
            TargetLengthProduct = 25.0
            MinimumComponent = 1
            Rounding = 'Ceiling'
        }

        DenseScfLengthProduct35 = @{
            Description = 'Denser SCF/DOS mesh for more stable energies and charge density.'
            Style = 'Gamma'
            TargetLengthProduct = 35.0
            MinimumComponent = 1
            Rounding = 'Ceiling'
        }

        BandLineMode = @{
            Description = 'Band calculations use a user-specified high-symmetry line path, not an automatic Monkhorst-Pack grid.'
            Style = 'Line-mode'
            RequiresManualPath = $true
        }
    }

    Notes = @(
        'For slabs or molecules, keep the vacuum-direction grid small only when the cell length is physically vacuum.'
        'For metals, magnetic systems, or small cells, convergence testing can require a denser mesh than the default target.'
    )
}
