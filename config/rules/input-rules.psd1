@{
    SchemaVersion = 1

    RequiredFiles = @('INCAR', 'POSCAR', 'KPOINTS', 'POTCAR')

    Geometry = @{
        MinimumCovalentRatio = 0.65
        AbsoluteMinimumDistanceAngstrom = 0.5
        CovalentRadiiAngstrom = @{
            H=0.31; He=0.28; Li=1.28; Be=0.96; B=0.84; C=0.76; N=0.71; O=0.66; F=0.57; Ne=0.58
            Na=1.66; Mg=1.41; Al=1.21; Si=1.11; P=1.07; S=1.05; Cl=1.02; Ar=1.06
            K=2.03; Ca=1.76; Sc=1.70; Ti=1.60; V=1.53; Cr=1.39; Mn=1.39; Fe=1.32; Co=1.26; Ni=1.24
            Cu=1.32; Zn=1.22; Ga=1.22; Ge=1.20; As=1.19; Se=1.20; Br=1.20; Kr=1.16
            Rb=2.20; Sr=1.95; Y=1.90; Zr=1.75; Nb=1.64; Mo=1.54; Tc=1.47; Ru=1.46; Rh=1.42; Pd=1.39
            Ag=1.45; Cd=1.44; In=1.42; Sn=1.39; Sb=1.39; Te=1.38; I=1.39; Xe=1.40
            Cs=2.44; Ba=2.15; La=2.07; Ce=2.04; Pr=2.03; Nd=2.01; Pm=1.99; Sm=1.98; Eu=1.98; Gd=1.96
            Tb=1.94; Dy=1.92; Ho=1.92; Er=1.89; Tm=1.90; Yb=1.87; Lu=1.87
            Hf=1.75; Ta=1.70; W=1.62; Re=1.51; Os=1.44; Ir=1.41; Pt=1.36; Au=1.36; Hg=1.32
            Tl=1.45; Pb=1.46; Bi=1.48; Po=1.40; At=1.50; Rn=1.50
            Fr=2.60; Ra=2.21; Ac=2.15; Th=2.06; Pa=2.00; U=1.96; Np=1.90; Pu=1.87; Am=1.80; Cm=1.69
        }
    }

    AutoDetection = @{
        DefaultCalculationType = 'Scf'
        Checks = @(
            @{ CalculationType='Band'; Kind='KpointsRegex'; Pattern='(?im)^\s*line-?mode\s*$' }
            @{ CalculationType='Band'; Kind='IncarEquals'; Key='ICHARG'; Value='11' }
            @{ CalculationType='Relax'; Kind='IncarIntegerGreaterThan'; Key='NSW'; Value=0 }
        )
    }

    CalculationTypes = @{
        Relax = @{
            Checks = @(
                @{ Kind='IncarIntegerGreaterThan'; Key='NSW'; Value=0; Severity='Warning'; Message='Relax calculation does not set NSW to a positive value.' }
            )
        }
        Scf = @{
            Checks = @(
                @{ Kind='IncarIntegerEquals'; Key='NSW'; Value=0; AllowMissing=$true; Severity='Error'; Message='Scf calculation must use NSW=0.' }
            )
        }
        Static = @{
            Checks = @(
                @{ Kind='IncarIntegerEquals'; Key='NSW'; Value=0; AllowMissing=$true; Severity='Error'; Message='Static calculation must use NSW=0.' }
            )
        }
        Band = @{
            Checks = @(
                @{ Kind='IncarEquals'; Key='ICHARG'; Value='11'; Severity='Error'; Message='Band calculation must use ICHARG=11.' }
                @{ Kind='KpointsRegex'; Pattern='(?im)^\s*line-?mode\s*$'; Severity='Error'; Message='Band calculation KPOINTS must use Line-mode.' }
                @{ Kind='IncarIntegerEquals'; Key='NSW'; Value=0; AllowMissing=$true; Severity='Error'; Message='Band calculation must use NSW=0.' }
                @{ Kind='AnyFileExists'; Files=@('CHGCAR', 'prepare_stage.sh'); Severity='Warning'; Message='Band calculation has neither a local CHGCAR nor prepare_stage.sh to copy one at runtime.' }
            )
        }
    }
}
