module LateralTranspMod
  use data_kind_mod,    only: r8 => DAT_KIND_R8
  USE abortutils,       only: endrun
  use EcoSiMParDataMod, only: micpar
  use minimathmod,      only: AZMAX1
  use EcoSIMConfig,     only: jcplx => jcplxc, NumMicbFunGrupsPerCmplx=>NumMicbFunGrupsPerCmplx
  use EcoSIMConfig,     only: nlbiomcp=>NumLiveMicrbCompts
  use TracerPropMod,    only: MolecularWeight
  use ClimForcDataType, only: PBOT_col
  use DebugToolMod
  use GridDataType
  use RedistDataMod
  use TracerIDMod
  use SoilBGCDataType
  use SoilWaterDataType
  use ChemTranspDataType
  use SnowDataType
  USE AqueChemDatatype
  USE EcoSIMCtrlDataType
  USE SedimentDataType
  USE MicrobialDataType
  USE SurfSoilDataType
  use SoilPropertyDataType
  use FlagDataType
  USE SoilHeatDataType
  use EcoSimConst
  use ErosionBalMod
  use SnowBalanceMod
  use SnowTransportMod
  use EcoSIMCtrlMod
implicit none
  private
  character(len=*), parameter :: mod_filename = &
  __FILE__

  public :: XGridTranspt
  contains

  subroutine XGridTranspt(I,J,NY,NX,LG)
  !
  ! Description:
  ! Energy and material transport across grids
  !
  implicit none
  integer, intent(in) :: I,J,NY,NX
  integer, intent(out) :: LG       !lbubble deposition layer

  character(len=*), parameter :: subname='XGridTranspt'
  integer :: L,N
  logical :: doBubble                    !potential bubbling detection flag
  integer :: N1,N2,N3,N4,N5,N6
  integer :: N4B,N5B
  integer :: idg
  real(r8) :: VTATM,VTGAS
  real(r8) :: trcg_VOLG(idg_beg:idg_end)   !mole of gas in layer [mol gas d-2]
  real(r8) :: dPond                        !hydrostatic pressure due to ponding water

! begin_execution
  call PrintInfo('beg '//subname)

  call ZeroFluxArrays(NY,NX)

  call ZeroFluxAccumulators(NY,NX)

  LG=0;doBubble=.false.

  D8575: DO L=NU(NY,NX),NL(NY,NX)
    !
    !     IDENTIFY LAYERS FOR BUBBLE FLUX TRANSFER
    !
!
    DO idg=idg_beg,idg_NH3
      trcg_VOLG(idg_CO2) = trcg_gasml_vr(idg_CO2,L,NY,NX)/MolecularWeight(idg)
    ENDDO

    if(iPondFlag_col(NY,NX))then 
      !grid is a pond
      if(SoilBulkDensity_vr(L,NY,NX).LE.ZERO)then
        !still in the ponding water, \rho*g*h,  1.e3*10
        dPond=(CumDepz2LayBottom_vr(L,NY,NX)-CumDepz2LayBottom_vr(NU(NY,NX)-1,NY,NX))*10._r8
      else
        !in the soil
        dPond=(CumDepz2LayBottom_vr(iPondBotLev_col(NY,NX),NY,NX)-CumDepz2LayBottom_vr(NU(NY,NX)-1,NY,NX))*10._r8
      endif  
    endif  

    VTATM=AZMAX1((PBOT_col(NY,NX)+dPond)*VLsoiAirP_vr(L,NY,NX)/(RgasC*TKS_vr(L,NY,NX)))*1.E3_r8 !mol gas/ d2

!   NH3B does not have explicit gas species, so there is an inconsistency
!   with respect to the actual ebullition calculation, which involves
!   NH3B

    VTGAS=sum(trcg_VOLG(idg_beg:idg_NH3))

    !air-concentration insignificant, or total gas volume > allwed air
    !LX==1, then too less air, or gas pressure > atmosphere
    !AirFillPore_Min minimum air-filled porosity

    !current layer has too small air volume (aka saturated), or gas pressure is greater than atmospheric pressure
    IF(ThetaAir_vr(L,NY,NX).LT.AirFillPore_Min .OR. VTGAS.GT.VTATM)doBubble=.true.

    !current layer has enough air, and there is not bubbling layer above, so set current layer
    !as the bubble depsoition layer 
    IF(ThetaAir_vr(L,NY,NX).GE.AirFillPore_Min .AND. (.not. doBubble))LG=L

!
  !     NET WATER, HEAT, GAS, SOLUTE, SEDIMENT FLUX
  !
  !     N3,N2,N1=L,NY,NX of source grid cell
  !     N6,N5,N4=L,NY,NX of destination grid cell
  ! source
    N1=NX;N2=NY;N3=L
    D8580: DO N=FlowDirIndicator(NY,NX),3
      !Exchange in the x direction, west-east        
      IF(N.EQ.iEastWestDirection)THEN 
        N4  = NX+1   !east
        N5  = NY
        N4B = NX-1   !west
        N5B = NY
        N6  = L
      !Exchange in the y direction, north-south 
      ELSEIF(N.EQ.iNorthSouthDirection)THEN  
        N4  = NX
        N5  = NY+1    !south
        N4B = NX
        N5B = NY-1    !north
        N6  = L
      !Vertical  
      ELSEIF(N.EQ.iVerticalDirection)THEN       
        N4 = NX
        N5 = NY
        N6 = L+1
      ENDIF
!
      !top soil layer/land surface
      IF(L.EQ.NUM(N2,N1))THEN
        !top layer runoff
        IF(N.NE.iVerticalDirection)THEN
          !horizontal exchange
          call XGridDOMRunoff(N,N1,N2,N4,N5,N4B,N5B)

          call XGridTracerRunoff(N,N1,N2,N4,N5,N4B,N5B)

          call XGridSnowTracerRunoff(N,N1,N2,N4,N5,N4B,N5B)
          !
        ELSEIF(N.EQ.iVerticalDirection)THEN
          !vertical direction
          call SaltPercolThruSnow(I,J,N1,N2)
        ENDIF
!
        ! TOTAL FLUXES FROM SEDIMENT TRANSPORT
        call SumSedmentTranspFlux(N,N1,N2,N4,N5,N4B,N5B)
      ENDIF
!
      call FlowXGrids(I,J,N,N1,N2,N3,N4,N5,N6)
    ENDDO D8580
!
!     NET FREEZE-THAW
!
!     WatIceThawMicP,WatIceThawMacP_vr=net freeze-thaw flux in micropores,macropores
!     THeatSoiThaw=net freeze-thaw latent heat flux
!     THAW,TLIceThawMacP=freeze-thaw flux in micropores,macropores from watsub.f
!     TLPhaseChangeHeat2Soi=freeze-thaw latent heat flux from watsub.f

    WatIceThawMicP_vr(N3,N2,N1) = WatIceThawMicP_vr(N3,N2,N1)+TLIceThawMicP_vr(N3,N2,N1)
    WatIceThawMacP_vr(N3,N2,N1) = WatIceThawMacP_vr(N3,N2,N1)+TLIceThawMacP_vr(N3,N2,N1)
    THeatSoiThaw_vr(N3,N2,N1)   = THeatSoiThaw_vr(N3,N2,N1)+TLPhaseChangeHeat2Soi_vr(N3,N2,N1)
  ENDDO D8575

  call PrintInfo('end '//subname)
  end subroutine XGridTranspt

!------------------------------------------------------------------------------------------

  subroutine ZeroRunoffArray(NY,NX)
  implicit none
  integer, intent(in) :: NY,NX
  integer :: L,K
!
!     INITIALIZE NET WATER AND HEAT FLUXES FOR RUNOFF
!
!
!     INITIALIZE NET SOLUTE AND GAS FLUXES FOR RUNOFF
!
  D9960: DO K=1,micpar%NumOfLitrCmplxs
    DOM_SurfRunoff_flx(idom_beg:idom_end,K,NY,NX)=0.0_r8
  ENDDO D9960

  trcn_SurfRunoff_flx(ids_nut_beg:ids_nuts_end,NY,NX)     = 0.0_r8
  trcg_SurfRunoff_flx(idg_beg:idg_NH3,NY,NX)              = 0.0_r8
  if(salt_model) trcSalt_SurfRunoff_flx(idsalt_beg:idsalt_end,NY,NX)=0.0_r8
  end subroutine ZeroRunoffArray

!------------------------------------------------------------------------------------------

  subroutine ZeroFluxArrays(NY,NX)
  implicit none
  integer, intent(in) :: NY,NX
  integer :: M,NO,NGL
!     begin_execution

  call ZeroRunoffArray(NY,NX)

!     INITIALIZE NET SNOWPACK FLUXES WITHIN SNOWPACK

  call ZeroSnowArrays(NY,NX)

!
!     INITIALIZE NET SEDIMENT FLUXES FROM EROSION
!
  call ZeroErosionArray(NY,NX)

  end subroutine ZeroFluxArrays

!------------------------------------------------------------------------------------------

  subroutine ZeroFluxAccumulators(NY,NX)
  implicit none
  integer, intent(in) :: NY,NX

  integer :: K,L
!     begin_execution
!
!     INITIALIZE WATER AND HEAT NET FLUX ACCUMULATORS WITHIN SOIL
!
  DO  L=NU(NY,NX),NL(NY,NX)
    TWatFlowCellMicP_vr(L,NY,NX)  = 0.0_r8
    TWatFlowCellMicPX_vr(L,NY,NX) = 0.0_r8
    TWatFlowCellMacP_vr(L,NY,NX)  = 0.0_r8
    THeatFlowCellSoil_vr(L,NY,NX) = 0.0_r8
    WatIceThawMicP_vr(L,NY,NX)    = 0.0_r8
    WatIceThawMacP_vr(L,NY,NX)    = 0.0_r8
    THeatSoiThaw_vr(L,NY,NX)      = 0.0_r8
!
!     INITIALIZE GAS AND SOLUTE NET FLUX ACCUMULATORS WITHIN SOIL
!
    D8595: DO K=1,jcplx
      DOM_Transp2Micp_vr(idom_beg:idom_end,K,L,NY,NX)  = 0.0_r8
      DOM_Transp2Macp_flx(idom_beg:idom_end,K,L,NY,NX) = 0.0_r8
    ENDDO D8595

    trcs_TransptMicP_vr(ids_beg:ids_end,L,NY,NX) = 0.0_r8
    trcs_TransptMacP_vr(ids_beg:ids_end,L,NY,NX) = 0.0_r8
    Gas_AdvDif_Flx_vr(idg_beg:idg_NH3,L,NY,NX)   = 0.0_r8

    IF(salt_model)THEN
      trcSalt_Flo2MicP_vr(idsalt_beg:idsaltb_end,L,NY,NX) = 0.0_r8
      trcSalt_Flo2MacP_vr(idsalt_beg:idsaltb_end,L,NY,NX) = 0.0_r8
    ENDIF
  ENDDO
  end subroutine ZeroFluxAccumulators

!------------------------------------------------------------------------------------------
  subroutine XGridTracerRunoff(N,N1,N2,N4,N5,N4B,N5B)

  implicit none
  integer, intent(in) :: N        !direction indicator, N=3: vertical, otherwise:horizontal
  integer, intent(in) :: N1,N2    !current grid
  integer, intent(in) :: N4,N5    !front
  integer, intent(in) :: N4B,N5B  !back

  character(len=*), parameter :: subname='XGridTracerRunoff'
  integer :: NN,idg,idn,idsalt
  
  call PrintInfo('beg '//subname)
  !NN=1:iOutflow, 2:iInflow
  D1202: DO NN=1,2
    !gaseous tracers
    DO idg=idg_beg,idg_NH3
      trcg_SurfRunoff_flx(idg,N2,N1)=trcg_SurfRunoff_flx(idg,N2,N1)+trcg_FloXSurRunoff_2D(idg,N,NN,N2,N1)      
    ENDDO

    !nutrient tracres
    DO idn=ids_nut_beg,ids_nuts_end
      trcn_SurfRunoff_flx(idn,N2,N1)=trcn_SurfRunoff_flx(idn,N2,N1)+trcn_FloXSurRunoff_2D(idn,N,NN,N2,N1)
    ENDDO

    IF(IFLBH(N,NN,N5,N4).EQ.0)THEN    

      DO idg=idg_beg,idg_NH3
        trcg_SurfRunoff_flx(idg,N2,N1)=trcg_SurfRunoff_flx(idg,N2,N1)-trcg_FloXSurRunoff_2D(idg,N,NN,N5,N4)
      ENDDO
      DO idn=ids_nut_beg,ids_nuts_end
        trcn_SurfRunoff_flx(idn,N2,N1)=trcn_SurfRunoff_flx(idn,N2,N1)-trcn_FloXSurRunoff_2D(idn,N,NN,N5,N4)
      ENDDO

    ENDIF 

    IF(N4B.GT.0 .AND. N5B.GT.0 .AND. NN.EQ.iOutflow)THEN
      DO idg=idg_beg,idg_NH3
        trcg_SurfRunoff_flx(idg,N2,N1)=trcg_SurfRunoff_flx(idg,N2,N1)-trcg_FloXSurRunoff_2D(idg,N,NN,N5B,N4B)
      ENDDO
      DO idn=ids_nut_beg,ids_nuts_end
        trcn_SurfRunoff_flx(idn,N2,N1)=trcn_SurfRunoff_flx(idn,N2,N1)-trcn_FloXSurRunoff_2D(idn,N,NN,N5B,N4B)
      ENDDO
    ENDIF
  ENDDO D1202

  if(salt_model)then
    D1203: DO NN=1,2
      DO idsalt=idsalt_beg,idsalt_end
        trcSalt_SurfRunoff_flx(idsalt,N2,N1)=trcSalt_SurfRunoff_flx(idsalt,N2,N1)+trcSalt_FloXSurRunoff_2D(idsalt,N,NN,N2,N1)
      ENDDO

      IF(IFLBH(N,NN,N5,N4).EQ.0)THEN
! runoff direction
        DO idsalt=idsalt_beg,idsalt_end
          trcSalt_SurfRunoff_flx(idsalt,N2,N1)=trcSalt_SurfRunoff_flx(idsalt,N2,N1)-trcSalt_FloXSurRunoff_2D(idsalt,N,NN,N5,N4)
        ENDDO
      ENDIF

      IF(N4B.GT.0 .AND. N5B.GT.0 .AND. NN.EQ.iOutflow)THEN
        DO idsalt=idsalt_beg,idsalt_end
          trcSalt_SurfRunoff_flx(idsalt,N2,N1)=trcSalt_SurfRunoff_flx(idsalt,N2,N1)-trcSalt_FloXSurRunoff_2D(idsalt,N,NN,N5B,N4B)
        ENDDO
      ENDIF
    ENDDO D1203
  endif
  call PrintInfo('end '//subname)
  end subroutine XGridTracerRunoff
!------------------------------------------------------------------------------------------

  subroutine XGridDOMRunoff(N,N1,N2,N4,N5,N4B,N5B)
  !
  !Description
  !Inner grid runoff
  !
  implicit none
  integer, intent(in) :: N,N1,N2,N4,N5,N4B,N5B

  integer :: NN,K,idg,NTN,idom
  !     begin_execution
  !     NET WATER, SNOW AND HEAT FLUXES FROM RUNOFF
  !
  !NN=1:iOutflow, 2:iInflow
  D1202: DO NN=1,2
        
    !water flux
    D8590: DO K=1,micpar%NumOfLitrCmplxs
      DO idom=idom_beg,idom_end
        DOM_SurfRunoff_flx(idom,K,N2,N1)=DOM_SurfRunoff_flx(idom,K,N2,N1)+DOM_FloXSurRunoff_2D(idom,K,N,NN,N2,N1)
      ENDDO
    ENDDO D8590

    IF(IFLBH(N,NN,N5,N4).EQ.0)THEN
      !there is lateral runoff
      !water flux
      D8591: DO K=1,micpar%NumOfLitrCmplxs
        DO idom=idom_beg,idom_end
          DOM_SurfRunoff_flx(idom,K,N2,N1)=DOM_SurfRunoff_flx(idom,K,N2,N1)-DOM_FloXSurRunoff_2D(idom,K,N,NN,N5,N4)
        ENDDO
      ENDDO D8591

    ENDIF

    IF(N4B.GT.0 .AND. N5B.GT.0 .AND. NN.EQ.iOutflow)THEN
      D8592: DO K=1,micpar%NumOfLitrCmplxs
        DO idom=idom_beg,idom_end
          DOM_SurfRunoff_flx(idom,K,N2,N1)=DOM_SurfRunoff_flx(idom,K,N2,N1)-DOM_FloXSurRunoff_2D(idom,K,N,NN,N5B,N4B)
        enddo
      ENDDO D8592
    ENDIF
  ENDDO D1202

  end subroutine XGridDOMRunoff
!------------------------------------------------------------------------------------------

  subroutine SumSedmentTranspFlux(N,N1,N2,N4,N5,N4B,N5B)
  implicit none
  integer, intent(in) :: N       !direction of calculation, west-east, or north-south
  integer, intent(in) :: N1,N2   !current grid
  integer, intent(in) :: N4,N5   !front grid (->east or ->south)
  integer, intent(in) :: N4B,N5B !back grid  (<-west or <-north)

  integer :: M,K,NO,NN,NGL,idx,NTP,MID,NE,idom
!     begin_execution
!
!
  IF(N.NE.iVerticalDirection .AND. (iErosionMode.EQ.ieros_frzthaweros .OR. iErosionMode.EQ.ieros_frzthawsomeros))THEN
    !horizontal direction
    !
    D9350: DO NN=1,2
      IF(ABS(cumSed_Eros_2D(N,NN,N2,N1)).GT.ZEROS(N2,N1) &             !grid (N2,N1) has erosion removal
        .OR. ABS(cumSed_Eros_2D(N,NN,N5,N4)).GT.ZEROS(N5,N4))THEN      !grid (N5,N4) has erosion removal

        !incoming from south or east grid 
        tErosionSedmLoss_col(N2,N1) = tErosionSedmLoss_col(N2,N1)+cumSed_Eros_2D(N,NN,N2,N1)
        TSandEros_col(N2,N1)        = TSandEros_col(N2,N1)+XSand_Eros_2D(N,NN,N2,N1)
        TSiltEros_col(N2,N1)        = TSiltEros_col(N2,N1)+XSilt_Eros_2D(N,NN,N2,N1)
        TCLAYEros_col(N2,N1)        = TCLAYEros_col(N2,N1)+XClay_Eros_2D(N,NN,N2,N1)
        TNH4Eros_col(N2,N1)         = TNH4Eros_col(N2,N1)+XNH4Soil_Eros_2D(N,NN,N2,N1)
        TNH3Eros_col(N2,N1)         = TNH3Eros_col(N2,N1)+XNH3Soil_Eros_2D(N,NN,N2,N1)
        TNUreaEros_col(N2,N1)       = TNUreaEros_col(N2,N1)+XUreaSoil_Eros_2D(N,NN,N2,N1)
        TNO3Eros_col(N2,N1)         = TNO3Eros_col(N2,N1)+XNO3Soil_Eros_2D(N,NN,N2,N1)
        TNH4ErosBand_col(N2,N1)     = TNH4ErosBand_col(N2,N1)+XNH4Band_Eros_2D(N,NN,N2,N1)
        TNH3ErosBand_col(N2,N1)     = TNH3ErosBand_col(N2,N1)+XNH3Band_Eros_2D(N,NN,N2,N1)
        TNUreaErosBand_col(N2,N1)   = TNUreaErosBand_col(N2,N1)+XUreaBand_Eros_2D(N,NN,N2,N1)
        TNO3ErosBand_col(N2,N1)     = TNO3ErosBand_col(N2,N1)+XNO3Band_Eros_2D(N,NN,N2,N1)

        DO idx=idx_beg,idx_end
          trcx_TER_col(idx,N2,N1)=trcx_TER_col(idx,N2,N1)+trcx_Eros_2D(idx,N,NN,N2,N1)
        ENDDO

        DO NTP=idsp_beg,idsp_end
          trcp_TER_col(NTP,N2,N1)=trcp_TER_col(NTP,N2,N1)+trcp_Eros_2D(NTP,N,NN,N2,N1)
        ENDDO

        DO  K=1,jcplx
          DO NO=1,NumMicbFunGrupsPerCmplx
            DO NGL=JGnio(NO),JGnfo(NO)
              DO M=1,nlbiomcp
                MID=micpar%get_micb_id(M,NGL)
                DO NE=1,NumPlantChemElms
                  TOMEERhetr_col(NE,MID,K,N2,N1)=TOMEERhetr_col(NE,MID,K,N2,N1)+OMEERhetr(NE,MID,K,N,NN,N2,N1)
                ENDDO  
              enddo
            enddo
          enddo
        ENDDO

        DO NO=1,NumMicbFunGrupsPerCmplx
          DO NGL=JGniA(NO),JGnfA(NO)
            DO M=1,nlbiomcp
              MID=micpar%get_micb_id(M,NGL)
              DO NE=1,NumPlantChemElms
                TOMEERauto_col(NE,MID,N2,N1)=TOMEERauto_col(NE,MID,N2,N1)+OMEERauto(NE,MID,N,NN,N2,N1)
              ENDDO  
            enddo
          enddo
        enddo

        D9375: DO K=1,jcplx
          D9370: DO M=1,ndbiomcp
            DO NE=1,NumPlantChemElms
              TORMER_col(NE,M,K,N2,N1)=TORMER_col(NE,M,K,N2,N1)+OMBioResdu_Eros_2D(NE,M,K,N,NN,N2,N1)
            ENDDO
          ENDDO D9370
          DO idom=idom_beg,idom_end
            TOHMER_col(idom,K,N2,N1)=TOHMER_col(idom,K,N2,N1)+SorbedOM_Eros_2D(idom,K,N,NN,N2,N1)
          ENDDO
          D9365: DO M=1,jsken
            TOSAER_col(M,K,N2,N1)=TOSAER_col(M,K,N2,N1)+SolidOMAct_Eros_2D(M,K,N,NN,N2,N1)
            DO NE=1,NumPlantChemElms
              TOSMER_col(NE,M,K,N2,N1)=TOSMER_col(NE,M,K,N2,N1)+SolidOM_Eros_2D(NE,M,K,N,NN,N2,N1) 
            ENDDO
          ENDDO D9365
        ENDDO D9375

!       outgoing
        tErosionSedmLoss_col(N2,N1) = tErosionSedmLoss_col(N2,N1)-cumSed_Eros_2D(N,NN,N5,N4)
        TSandEros_col(N2,N1)        = TSandEros_col(N2,N1)-XSand_Eros_2D(N,NN,N5,N4)
        TSiltEros_col(N2,N1)        = TSiltEros_col(N2,N1)-XSilt_Eros_2D(N,NN,N5,N4)
        TCLAYEros_col(N2,N1)        = TCLAYEros_col(N2,N1)-XClay_Eros_2D(N,NN,N5,N4)
        TNH4Eros_col(N2,N1)         = TNH4Eros_col(N2,N1)-XNH4Soil_Eros_2D(N,NN,N5,N4)
        TNH3Eros_col(N2,N1)         = TNH3Eros_col(N2,N1)-XNH3Soil_Eros_2D(N,NN,N5,N4)
        TNUreaEros_col(N2,N1)       = TNUreaEros_col(N2,N1)-XUreaSoil_Eros_2D(N,NN,N5,N4)
        TNO3Eros_col(N2,N1)         = TNO3Eros_col(N2,N1)-XNO3Soil_Eros_2D(N,NN,N5,N4)
        TNH4ErosBand_col(N2,N1)     = TNH4ErosBand_col(N2,N1)-XNH4Band_Eros_2D(N,NN,N5,N4)
        TNH3ErosBand_col(N2,N1)     = TNH3ErosBand_col(N2,N1)-XNH3Band_Eros_2D(N,NN,N5,N4)
        TNUreaErosBand_col(N2,N1)   = TNUreaErosBand_col(N2,N1)-XUreaBand_Eros_2D(N,NN,N5,N4)
        TNO3ErosBand_col(N2,N1)     = TNO3ErosBand_col(N2,N1)-XNO3Band_Eros_2D(N,NN,N5,N4)

        DO idx=idx_beg,idx_end
          trcx_TER_col(idx,N2,N1)=trcx_TER_col(idx,N2,N1)-trcx_Eros_2D(idx,N,NN,N5,N4)
        ENDDO

        DO NTP=idsp_beg,idsp_end
          trcp_TER_col(NTP,N2,N1)=trcp_TER_col(NTP,N2,N1)-trcp_Eros_2D(NTP,N,NN,N5,N4)
        ENDDO

        DO  K=1,jcplx
          DO  NO=1,NumMicbFunGrupsPerCmplx
            DO NGL=JGnio(NO),JGnfo(NO)
              DO  M=1,nlbiomcp
                MID=micpar%get_micb_id(M,NGL)
                DO NE=1,NumPlantChemElms
                  TOMEERhetr_col(NE,MID,K,N2,N1)=TOMEERhetr_col(NE,MID,K,N2,N1)-OMEERhetr(NE,MID,K,N,NN,N5,N4)
                ENDDO  
              enddo
            enddo
          enddo
        ENDDO

        DO  NO=1,NumMicbFunGrupsPerCmplx
          DO  M=1,nlbiomcp
            DO NGL=JGniA(NO),JGnfA(NO)
              MID=micpar%get_micb_id(M,NGL)   
              DO NE=1,NumPlantChemElms         
                TOMEERauto_col(NE,MID,N2,N1)=TOMEERauto_col(NE,MID,N2,N1)-OMEERauto(NE,MID,N,NN,N5,N4)
              ENDDO  
            enddo
          enddo
        enddo

        D7375: DO K=1,jcplx
          D7370: DO M=1,ndbiomcp
            DO NE=1,NumPlantChemElms
              TORMER_col(NE,M,K,N2,N1)=TORMER_col(NE,M,K,N2,N1)-OMBioResdu_Eros_2D(NE,M,K,N,NN,N5,N4)
            ENDDO
          ENDDO D7370
          DO idom=idom_beg,idom_end
            TOHMER_col(idom,K,N2,N1)=TOHMER_col(idom,K,N2,N1)-SorbedOM_Eros_2D(idom,K,N,NN,N5,N4)
          ENDDO
          D7365: DO M=1,jsken
            TOSAER_col(M,K,N2,N1)=TOSAER_col(M,K,N2,N1)-SolidOMAct_Eros_2D(M,K,N,NN,N5,N4)   
            DO NE=1,NumPlantChemElms       
              TOSMER_col(NE,M,K,N2,N1)=TOSMER_col(NE,M,K,N2,N1)-SolidOM_Eros_2D(NE,M,K,N,NN,N5,N4)
            ENDDO
          ENDDO D7365
        ENDDO D7375
      ENDIF

      IF(N4B.GT.0 .AND. N5B.GT.0 .AND. NN.EQ.iOutflow)THEN
        IF(ABS(cumSed_Eros_2D(N,NN,N5B,N4B)).GT.ZEROS(N5,N4))THEN
          tErosionSedmLoss_col(N2,N1) = tErosionSedmLoss_col(N2,N1)-cumSed_Eros_2D(N,NN,N5B,N4B)
          TSandEros_col(N2,N1)        = TSandEros_col(N2,N1)-XSand_Eros_2D(N,NN,N5B,N4B)
          TSiltEros_col(N2,N1)        = TSiltEros_col(N2,N1)-XSilt_Eros_2D(N,NN,N5B,N4B)
          TCLAYEros_col(N2,N1)        = TCLAYEros_col(N2,N1)-XClay_Eros_2D(N,NN,N5B,N4B)
          TNH4Eros_col(N2,N1)         = TNH4Eros_col(N2,N1)-XNH4Soil_Eros_2D(N,NN,N5B,N4B)
          TNH3Eros_col(N2,N1)         = TNH3Eros_col(N2,N1)-XNH3Soil_Eros_2D(N,NN,N5B,N4B)
          TNUreaEros_col(N2,N1)       = TNUreaEros_col(N2,N1)-XUreaSoil_Eros_2D(N,NN,N5B,N4B)
          TNO3Eros_col(N2,N1)         = TNO3Eros_col(N2,N1)-XNO3Soil_Eros_2D(N,NN,N5B,N4B)
          TNH4ErosBand_col(N2,N1)     = TNH4ErosBand_col(N2,N1)-XNH4Band_Eros_2D(N,NN,N5B,N4B)
          TNH3ErosBand_col(N2,N1)     = TNH3ErosBand_col(N2,N1)-XNH3Band_Eros_2D(N,NN,N5B,N4B)
          TNUreaErosBand_col(N2,N1)   = TNUreaErosBand_col(N2,N1)-XUreaBand_Eros_2D(N,NN,N5B,N4B)
          TNO3ErosBand_col(N2,N1)     = TNO3ErosBand_col(N2,N1)-XNO3Band_Eros_2D(N,NN,N5B,N4B)

          DO idx=idx_beg,idx_end
            trcx_TER_col(idx,N2,N1)=trcx_TER_col(idx,N2,N1)-trcx_Eros_2D(idx,N,NN,N5B,N4B)
          ENDDO

          DO NTP=idsp_beg,idsp_end
            trcp_TER_col(NTP,N2,N1)=trcp_TER_col(NTP,N2,N1)-trcp_Eros_2D(NTP,N,NN,N5B,N4B)
          ENDDO

          D8380: DO K=1,jcplx
            DO  NO=1,NumMicbFunGrupsPerCmplx
              DO NGL=JGnio(NO),JGnfo(NO)
                DO  M=1,nlbiomcp
                  MID=micpar%get_micb_id(M,NGL)    
                  DO NE=1,NumPlantChemElms            
                    TOMEERhetr_col(NE,MID,K,N2,N1)=TOMEERhetr_col(NE,MID,K,N2,N1)-OMEERhetr(NE,MID,K,N,NN,N5B,N4B)
                  ENDDO  
                enddo
              enddo
            enddo
          ENDDO D8380

          DO  NO=1,NumMicbFunGrupsPerCmplx
            DO NGL=JGniA(NO),JGnfA(NO)
              DO  M=1,nlbiomcp
                MID=micpar%get_micb_id(M,NGL)      
                DO NE=1,NumPlantChemElms        
                  TOMEERauto_col(NE,MID,N2,N1)=TOMEERauto_col(NE,MID,N2,N1)-OMEERauto(NE,MID,N,NN,N5B,N4B)
                ENDDO  
              enddo
            enddo
          enddo

          D8375: DO K=1,jcplx
            D8370: DO M=1,ndbiomcp
              DO NE=1,NumPlantChemElms
                TORMER_col(NE,M,K,N2,N1)=TORMER_col(NE,M,K,N2,N1)-OMBioResdu_Eros_2D(NE,M,K,N,NN,N5B,N4B)
              ENDDO
            ENDDO D8370
            DO idom=idom_beg,idom_end
              TOHMER_col(idom,K,N2,N1)=TOHMER_col(idom,K,N2,N1)-SorbedOM_Eros_2D(idom,K,N,NN,N5B,N4B)
            ENDDO
            D8365: DO M=1,jsken
              TOSAER_col(M,K,N2,N1)=TOSAER_col(M,K,N2,N1)-SolidOMAct_Eros_2D(M,K,N,NN,N5B,N4B)          
              DO NE=1,NumPlantChemElms  
                TOSMER_col(NE,M,K,N2,N1)=TOSMER_col(NE,M,K,N2,N1)-SolidOM_Eros_2D(NE,M,K,N,NN,N5B,N4B)
              ENDDO
            ENDDO D8365
          ENDDO D8375
        ENDIF
      ENDIF
    ENDDO D9350
  ENDIF
  end subroutine SumSedmentTranspFlux
!------------------------------------------------------------------------------------------

  subroutine FlowXGrids(I,J,N,N1,N2,N3,N4,N5,N6)
  !
  !Description
  !Flow across grids, can be in any of the three directions
  implicit none
  integer, intent(in) :: I,J
  integer, intent(in) :: N          !exchagne along direction, 1 east-west, 2 north-south, 3 vertical
  integer, intent(in) :: N1,N2,N3   !source soil grid indices
  integer, intent(in) :: N4,N5      !dest grid indices  
  integer, intent(inout) :: N6      !vertical layer 
  integer :: LL,K,idsalt,ids,idg,idom

  !     begin_execution
  !     NET HEAT, WATER FLUXES BETWEEN ADJACENT
  !     GRID CELLS
  !
  !     TFLW,TWatFlowCellMacP_vr,TWatFlowCellMacP_vr=net micropore,macropore water flux, heat flux
  !     FLW,FLWH,HFLW=micropore,macropore water flux, heat flux from watsub.f
  !     LakeSurfFlowMicP,FLWHNU,LakeSurfHeatFlux=lake surface water flux, heat flux from watsub.f if lake surface disappears
  !     when FlowDirIndicator /=3, it means lateral exchange is consdiered

  IF(FlowDirIndicator(N2,N1).NE.iVerticalDirection .OR. N.EQ.iVerticalDirection)THEN
    !locate the vertical layer for the dest grid
    D1200: DO LL=N6,NL(N5,N4)
      !modify the dest grid vertical location if needed
      !by matching the vertical layer number between source and dest, if N/=3
      !if N==3, skip insignificant layers
      IF(VLSoilPoreMicP_vr(LL,N2,N1).GT.ZEROS2(N2,N1))THEN
        N6=LL
        exit
      ENDIF
    ENDDO D1200

    IF(VLSoilPoreMicP_vr(N3,N2,N1).GT.ZEROS2(N2,N1))THEN
      !vertical direction transport, source is at soil surface
      IF(N3.EQ.NU(N2,N1) .AND. N.EQ.iVerticalDirection)THEN              
        TWatFlowCellMicP_vr(N3,N2,N1)  = TWatFlowCellMicP_vr(N3,N2,N1)+WaterFlowSoiMicP_3D(N,N3,N2,N1)-LakeSurfFlowMicP_col(N5,N4)
        TWatFlowCellMicPX_vr(N3,N2,N1) = TWatFlowCellMicPX_vr(N3,N2,N1)+WaterFlowSoiMicPX_3D(N,N3,N2,N1)-LakeSurfFlowMicPX_col(N5,N4)
        TWatFlowCellMacP_vr(N3,N2,N1)  = TWatFlowCellMacP_vr(N3,N2,N1)+WaterFlowSoiMacP_3D(N,N3,N2,N1)-LakeSurfFlowMacP_col(N5,N4)
        THeatFlowCellSoil_vr(N3,N2,N1) = THeatFlowCellSoil_vr(N3,N2,N1)+HeatFlow2Soil_3D(N,N3,N2,N1)-LakeSurfHeatFlux_col(N5,N4)

        if(THeatFlowCellSoil_vr(N3,N2,N1)<-1.e10)then
          write(*,*)'THeatFlowCellSoil_vr(N3,N2,N1)+HeatFlow2Soil_3D(N,N3,N2,N1)-LakeSurfHeatFlux_col(N5,N4)',&
            THeatFlowCellSoil_vr(N3,N2,N1),HeatFlow2Soil_3D(N,N3,N2,N1),LakeSurfHeatFlux_col(N5,N4)
          write(*,*)'Ns=',N1,n2,n3,n4,n5
          call endrun(trim(mod_filename)//' at line',__LINE__)
        endif
        !not vertical direction or source grid is not at surface
      ELSE
        TWatFlowCellMicP_vr(N3,N2,N1)  = TWatFlowCellMicP_vr(N3,N2,N1)+WaterFlowSoiMicP_3D(N,N3,N2,N1)-WaterFlowSoiMicP_3D(N,N6,N5,N4)
        TWatFlowCellMicPX_vr(N3,N2,N1) = TWatFlowCellMicPX_vr(N3,N2,N1)+WaterFlowSoiMicPX_3D(N,N3,N2,N1)-WaterFlowSoiMicPX_3D(N,N6,N5,N4)
        TWatFlowCellMacP_vr(N3,N2,N1)  = TWatFlowCellMacP_vr(N3,N2,N1)+WaterFlowSoiMacP_3D(N,N3,N2,N1)-WaterFlowSoiMacP_3D(N,N6,N5,N4)
        THeatFlowCellSoil_vr(N3,N2,N1) = THeatFlowCellSoil_vr(N3,N2,N1)+HeatFlow2Soil_3D(N,N3,N2,N1)-HeatFlow2Soil_3D(N,N6,N5,N4)

        if(THeatFlowCellSoil_vr(N3,N2,N1)<-1.e10)then
          write(*,*)'THeatFlowCellSoil_vr(N3,N2,N1)+HeatFlow2Soil_3D(N,N3,N2,N1)-HeatFlow2Soil_3D(N,N6,N5,N4)',&
            THeatFlowCellSoil_vr(N3,N2,N1),HeatFlow2Soil_3D(N,N3,N2,N1),HeatFlow2Soil_3D(N,N6,N5,N4)
          write(*,*)'Ns=',N,N1,n2,n3,n4,n5,n6
          call endrun(trim(mod_filename)//' at line',__LINE__)
        endif
      ENDIF
      !
      !     NET SOLUTE FLUXES BETWEEN ADJACENT GRID CELLS
      !
      D8585: DO K=1,jcplx
        do idom=idom_beg,idom_end
          DOM_Transp2Micp_vr(idom,K,N3,N2,N1)=DOM_Transp2Micp_vr(idom,K,N3,N2,N1) &
            +DOM_MicpTransp_3D(idom,K,N,N3,N2,N1)-DOM_MicpTransp_3D(idom,K,N,N6,N5,N4)
          DOM_Transp2Macp_flx(idom,K,N3,N2,N1)=DOM_Transp2Macp_flx(idom,K,N3,N2,N1) &
            +DOM_Macp_Transp_flx_3D(idom,K,N,N3,N2,N1)-DOM_Macp_Transp_flx_3D(idom,K,N,N6,N5,N4)
        enddo
      ENDDO D8585

      DO ids=ids_beg,ids_end
        trcs_TransptMicP_vr(ids,N3,N2,N1)=trcs_TransptMicP_vr(ids,N3,N2,N1) &
          +trcs_TransptMicP_3D(ids,N,N3,N2,N1)-trcs_TransptMicP_3D(ids,N,N6,N5,N4)
        trcs_TransptMacP_vr(ids,N3,N2,N1)=trcs_TransptMacP_vr(ids,N3,N2,N1) &
          +trcs_TransptMacP_3D(ids,N,N3,N2,N1)-trcs_TransptMacP_3D(ids,N,N6,N5,N4)

        if(abs(trcs_TransptMicP_vr(ids,N3,N2,N1))>1.e10)then
           write(*,*)ids,N3,N2,N1,N
           write(*,*)trcs_TransptMicP_3D(ids,N,N3,N2,N1),trcs_TransptMicP_3D(ids,N,N6,N5,N4)
           call endrun(trim(mod_filename)//' at line',__LINE__)
        endif
      ENDDO
      
      !summarize subsurface lateral tracer flow
      if(N.NE.iVerticalDirection)then
        DO idg=idg_beg,idg_end
          GasHydroLossFlx_col(idg,N2,N1)=GasHydroLossFlx_col(idg,N2,N1) + &
           trcs_TransptMicP_3D(idg,N,N3,N2,N1)-trcs_TransptMicP_3D(idg,N,N6,N5,N4) + &
           trcs_TransptMacP_3D(idg,N,N3,N2,N1)-trcs_TransptMacP_3D(idg,N,N6,N5,N4) + &
           Gas_AdvDif_Flx_3D(idg,N,N3,N2,N1)-Gas_AdvDif_Flx_3D(idg,N,N6,N5,N4)
        enddo
      endif
!
      !     NET GAS FLUXES BETWEEN ADJACENT GRID CELLS
      !exclude NH3B
      DO idg=idg_beg,idg_NH3
        Gas_AdvDif_Flx_vr(idg,N3,N2,N1)=Gas_AdvDif_Flx_vr(idg,N3,N2,N1) &
          +Gas_AdvDif_Flx_3D(idg,N,N3,N2,N1)-Gas_AdvDif_Flx_3D(idg,N,N6,N5,N4)
      ENDDO
!
      !     NET SALT FLUXES BETWEEN ADJACENT GRID CELLS
      IF(salt_model)THEN
        DO idsalt=idsalt_beg,idsaltb_end
          trcSalt_Flo2MicP_vr(idsalt,N3,N2,N1)=trcSalt_Flo2MicP_vr(idsalt,N3,N2,N1) &
            +trcSalt_TransptMicP_3D(idsalt,N,N3,N2,N1)-trcSalt_TransptMicP_3D(idsalt,N,N6,N5,N4)
          trcSalt_Flo2MacP_vr(idsalt,N3,N2,N1)=trcSalt_Flo2MacP_vr(idsalt,N3,N2,N1) &
            +trcSalt_TransptMacP_3D(idsalt,N,N3,N2,N1)-trcSalt_TransptMacP_3D(idsalt,N,N6,N5,N4)
        ENDDO
      ENDIF
    ELSE
      TWatFlowCellMicP_vr(N3,N2,N1)  = 0.0_r8
      TWatFlowCellMicPX_vr(N3,N2,N1) = 0.0_r8
      TWatFlowCellMacP_vr(N3,N2,N1)  = 0.0_r8
      THeatFlowCellSoil_vr(N3,N2,N1) = 0.0_r8
      WatIceThawMicP_vr(N3,N2,N1)    = 0.0_r8
      WatIceThawMacP_vr(N3,N2,N1)    = 0.0_r8
      THeatSoiThaw_vr(N3,N2,N1)      = 0.0_r8

      D8596: DO K=1,jcplx
        DOM_Transp2Micp_vr(idom_beg:idom_end,K,N3,N2,N1)  = 0.0_r8
        DOM_Transp2Macp_flx(idom_beg:idom_end,K,N3,N2,N1) = 0.0_r8
      ENDDO D8596

      trcs_TransptMicP_vr(ids_beg:ids_end,N3,N2,N1) = 0.0_r8
      trcs_TransptMacP_vr(ids_beg:ids_end,N3,N2,N1) = 0.0_r8
      Gas_AdvDif_Flx_vr(idg_beg:idg_NH3,N3,N2,N1)   = 0.0_r8

      IF(salt_model)THEN
        trcSalt_Flo2MicP_vr(idsalt_beg:idsaltb_end,N3,N2,N1) = 0.0_r8
        trcSalt_Flo2MacP_vr(idsalt_beg:idsaltb_end,N3,N2,N1) = 0.0_r8
      ENDIF
    ENDIF
  ENDIF
  end subroutine FlowXGrids

end module LateralTranspMod
