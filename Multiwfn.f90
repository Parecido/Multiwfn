program multiwfn
use defvar
use util
use GUI
implicit real*8(a-h,o-z)
character nowdate*20,nowtime*20,c200tmp*200,lovername*80,settingpath*200
real*8,allocatable :: tmparr(:),tmpmat(:,:)

call kmp_set_warnings_off() !In rare case, "Cannot open message catalog "1041\libiomp5ui.dll"" may occurs, this calling avoid this problem, or user should set KMP_WARNINGS environment variable to 0
call getarg(1,filename)
call getarg(2,cmdarg2)
10 call loadsetting
write(*,*) "Multiwfn -- A Multifunctional Wavefunction Analyzer"
write(*,*) "Version 3.6, release date: 2019-May-21"
write(*,"(a)") " Project leader: Tian Lu (Beijing Kein Research Center for Natural Sciences)"
write(*,*) "Below paper *MUST BE CITED* if Multiwfn is utilized in your work:"
write(*,*) "         Tian Lu, Feiwu Chen, J. Comput. Chem., 33, 580-592 (2012)"
write(*,*) "Multiwfn official website: http://sobereva.com/multiwfn"
write(*,*) "Multiwfn English forum: http://sobereva.com/wfnbbs"
write(*,*) "Multiwfn Chinese forum: http://bbs.keinsci.com/wfn"

if (isys==1) call KMP_SET_STACKSIZE_S(ompstacksize) !For Linux/MacOS version, it seems the only way to set stacksize of each thread is to define KMP_STACKSIZE environment variable
call date_and_time(nowdate,nowtime)
write(*,"(' ( The number of threads:',i3,'   Current date: ',a,'-',a,'-',a,'   Time: ',a,':',a,':',a,' )')") &
nthreads,nowdate(1:4),nowdate(5:6),nowdate(7:8),nowtime(1:2),nowtime(3:4),nowtime(5:6)
write(*,*)

if (trim(filename)=="") then !Haven't defined filename variable
	call mylover(lovername)
	write(*,"(a,a,a)") " Input file path, for example E:\",trim(lovername),".wfn"
	write(*,*) "(Supported: .wfn/.wfx/.fch/.molden/.31/.chg/.pdb/.xyz/.mol/.cub/.grd, etc.)"
	write(*,"(a)") " Hint: Press ENTER button directly can select file in a GUI window. To reload the file last time used, simply input the letter ""o"". &
	Input such as ?miku.fch can open the miku.fch in the same folder as the file last time used."
	do while(.true.)
		read(*,"(a)") filename
		if (filename=='o') then
			write(*,"(' The file last time used: ',a)") trim(lastfile)
			filename=lastfile
		else if (filename==' ') then
			call selfileGUI
			if (filename==' ') then
				write(*,*) "You did not select a file, input the path again!"
				cycle !User didn't select a file
			end if
			write(*,"(' Selected file: ',a)") trim(adjustl(filename))
		end if
		ltmp=len_trim(filename)
		!Remove the first and the last " or  'symbol, because directly dragging file into the window will result in " or ' symbol, which is unrecognized by Multwifn
		if (filename(1:1)=='"'.or.filename(1:1)=="'") filename(1:1)=" "
		if (filename(ltmp:ltmp)=='"'.or.filename(ltmp:ltmp)=="'") filename(ltmp:ltmp)=" "
		filename=adjustl(filename)
		if (filename(1:1)=='?') then
			do itmp=len_trim(lastfile),1,-1
				if (isys==1.and.lastfile(itmp:itmp)=='\') exit
				if (isys==2.and.lastfile(itmp:itmp)=='/') exit
			end do
			filename=lastfile(1:itmp)//trim(filename(2:))
		end if
		inquire(file=filename,exist=alive)
		if (alive.eqv..true.) exit
		write(*,"('""',a,'"" ',a)") trim(filename),"cannot be found, input again"
	end do
	!Write current opened file to "lastfile" in settings.ini
	inquire(file="settings.ini",exist=alive)
	if (alive==.true.) then
		settingpath="settings.ini"
	else if (alive==.false.) then
		call getenv("Multiwfnpath",c200tmp)
		if (isys==1) then
			settingpath=trim(c200tmp)//"\settings.ini"
		else if (isys==2) then
			settingpath=trim(c200tmp)//"/settings.ini"
		end if
	end if
	inquire(file=settingpath,exist=alive)
	if (alive) then
		open(20,file=settingpath,status="old")
		call loclabel(20,"lastfile")
		write(20,"(a)") "lastfile= "//trim(filename)
		close(20)
	end if
else
	inquire(file=filename,exist=alive)
	if (alive.eqv..false.) then
		write(*,*) "File not found, exit program..."
		read(*,*)
		stop
	end if
end if
call readinfile(filename,0)
write(*,"(/,3a)") " Loaded ",trim(filename)," successfully!"

!!-- Backup various information of first loaded (meanwhile unmodified) molecule
firstfilename=filename
if (allocated(a)) then
	allocate(a_org(ncenter))
	a_org=a
	ncenter_org=ncenter
end if
if (allocated(b)) then
	allocate(b_org(nprims))
	allocate(CO_org(nmo,nprims))
	allocate(MOocc_org(nmo))
	allocate(MOene_org(nmo))
	b_org=b
	CO_org=CO
	MOocc_org=MOocc
	MOene_org=MOene
	nprims_org=nprims
	nmo_org=nmo
end if

!!-- Initialize fragment
nfragatmnum=ncenter !Default fragment is the whole molecule
nfragatmnumbackup=ncenter
allocate(fragatm(nfragatmnum),fragatmbackup(nfragatmnum))
forall (i=1:nfragatmnum) fragatm(i)=i
forall (i=1:nfragatmnum) fragatmbackup(i)=i
ifragcontri=0

!!-- Call some routines only once
if (allocated(a)) then
	if (ncenter>5000) write(*,"(a)") " Warning: There are very large number of many atoms, please wait very patiently for generating distance matrix..."
	call gendistmat !Generate distance matrix
end if
!Convert prebuilt radii from Angstrom to Bohr. But some radii such as radii_hugo will remain unchanged since it is recorded as Bohr
if (ifirstMultiwfn==1) then
	vdwr=vdwr/b2a
	vdwr_tianlu=vdwr_tianlu/b2a
	vdwr_UFF=vdwr_UFF/b2a
	covr=covr/b2a
	covr_Suresh=covr_Suresh/b2a
	covr_pyy=covr_pyy/b2a
	covr_tianlu=covr_tianlu/b2a
end if
if (isys==2) call swgfnt("fixed",12) !In Linux, if font is not set for widget, the texts may not be displayed properly. Text size (12) is meaningless, since the size is bonded to font.
!Only get into dislin level 1 to get width and height of screen in pixels, don't do any other things
call METAFL("GKSL")
call disini
CALL GETSCR(iscrwidth,iscrheight)
call ERRMOD("ALL","OFF")
call disfin
CALL SYMFIL("NONE","DELETE")
!-- Show related molecular information
if (allocated(a)) then
	call showformula
	totmass=sum(atmwei(a%index))
	write(*,"(' Molecule weight:',f16.5)") totmass
end if


!Special treatment
! call sys1eprop !Show some system 1e properties, only works when Cartesian basis functions are presented
!allocate(tmpmat(ncenter,nmo))
!call CDFT

!!!--------------------- Now everything start ---------------------!!!
do while(.true.) !Main loop

	write(*,*)
	if (allocated(cubmat)) write(*,*) "Note: A set of grid data presents in memory"
	write(*,*) "                   ************ Main function menu ************"
	! write(*,*) "-11 Load a new file"
	! write(*,*) "-10 Exit program"
	if (ifiletype/=7.and.ifiletype/=8) write(*,*) "0 Show molecular structure and view orbitals"
	if (ifiletype==7.or.ifiletype==8) write(*,*) "0 Show molecular structure and view isosurface"
	write(*,*) "1 Output all properties at a point"
	write(*,*) "2 Topology analysis"
	write(*,*) "3 Output and plot specific property in a line"
	write(*,*) "4 Output and plot specific property in a plane"
	write(*,*) "5 Output and plot specific property within a spatial region (calc. grid data)"
	write(*,*) "6 Check & modify wavefunction"
	write(*,*) "7 Population analysis and atomic charges"
	write(*,*) "8 Orbital composition analysis"
	write(*,*) "9 Bond order analysis"
	write(*,*) "10 Plot total DOS, partial DOS, OPDOS, local DOS and photoelectron spectrum"
	write(*,*) "11 Plot IR/Raman/UV-Vis/ECD/VCD/ROA spectrum"
	write(*,*) "12 Quantitative analysis of molecular surface"
	if (allocated(cubmat)) write(*,*) "13 Process grid data"
	if (.not.allocated(cubmat)) write(*,*) "13 Process grid data (No grid data is presented currently)"
	write(*,*) "14 Adaptive natural density partitioning (AdNDP) analysis"
	write(*,*) "15 Fuzzy atomic space analysis"
	write(*,*) "16 Charge decomposition analysis (CDA) and extended CDA (ECDA)"
	write(*,*) "17 Basin analysis"
	write(*,*) "18 Electron excitation analysis"
	write(*,*) "19 Orbital localization analysis"
	write(*,*) "20 Visual study of weak interaction"
	write(*,*) "21 Energy decomposition analysis"
	write(*,*) "100 Other functions (Part1)        200 Other functions (Part2)"
	! write(*,*) "1000 Special functions"
	read(*,*) isel

	if (isel==-10) then !Exit program
		stop
	else if (isel==-11) then !Load a new file
		call dealloall
		call dealloall_org
		filename=""
		deallocate(fragatm,fragatmbackup)
		ifirstMultiwfn=0
		goto 10

	!!!---------------------------------------------------------------------------------------------
	!1!------- Show system structure and view isosurface of MOs or the grid data read from cube file
	else if (isel==0) then !
		if (.not.(allocated(a).or.allocated(cubmat))) then
			write(*,*) "Error: Data needed by this function is not presented! Check your input flie!"
			write(*,*) "Press ENTER button to continue"
			read(*,*)
			cycle
		end if
		if (ncenter>0) write(*,*) "Nucleus list:"
		do i=1,ncenter
			write(*,"(i5,'(',a2,')',' --> Charge:',f10.6,'  x,y,z(Bohr):',3f11.6)") i,a(i)%name,a(i)%charge,a(i)%x,a(i)%y,a(i)%z
		end do
		if (allocated(CObasa).and.imodwfn==0) then !fch and occupation number hasn't been modified
			if (wfntype==0) then
				write(*,"(' Note: Orbital',i6,' is HOMO, energy:',f12.6,' a.u.',f12.6,' eV')") nint(nelec/2),MOene(nint(nelec/2)),MOene(nint(nelec/2))*au2eV
				if (nint(nelec/2)+1<=nmo) then
					write(*,"('       Orbital',i6,' is LUMO, energy:',f12.6' a.u.',f12.6,' eV')") nint(nelec/2)+1,MOene(nint(nelec/2)+1),MOene(nint(nelec/2)+1)*au2eV
					gapene=MOene(nint(nelec/2)+1)-MOene(nint(nelec/2))
					write(*,"('       HOMO-LUMO gap:',f12.6,' a.u.',f12.6,' eV',f14.6,' kJ/mol')") gapene,gapene*au2eV,gapene*au2kJ
				end if
			else if (wfntype==1) then
				write(*,"(' Range of alpha orbitals:',i5,' -',i5,'      Range of Beta orbitals:',i5,' -',i5)") 1,nbasis,nbasis+1,nmo
				write(*,"(' Note: Orbital',i6,' is alpha-HOMO, energy:',f12.6,' a.u.',f12.6,' eV')") nint(naelec),MOene(nint(naelec)),MOene(nint(naelec))*au2eV
				write(*,"('       Orbital',i6,' is beta-HOMO, energy: ',f12.6,' a.u.',f12.6,' eV')") nbasis+nint(nbelec),MOene(nbasis+nint(nbelec)),MOene(nbasis+nint(nbelec))*au2eV
				if (nbasis>=nint(naelec)+1) then
					write(*,"('       Orbital',i6,' is alpha-LUMO, energy:',f12.6,' a.u.',f12.6,' eV')") nint(naelec)+1,MOene(nint(naelec)+1),MOene(nint(naelec)+1)*au2eV
					write(*,"('       Orbital',i6,' is beta-LUMO, energy: ',f12.6,' a.u.',f12.6,' eV')") nbasis+nint(nbelec)+1,MOene(nbasis+nint(nbelec)+1),MOene(nbasis+nint(nbelec)+1)*au2eV
					gapenea=MOene(nint(naelec)+1)-MOene(nint(naelec))
					write(*,"('       HOMO-LUMO gap of alpha orbitals:',f12.6,' a.u.',f12.6,' eV')") gapenea,gapenea*au2eV
					gapeneb=MOene(nbasis+nint(nbelec)+1)-MOene(nbasis+nint(nbelec))
					write(*,"('       HOMO-LUMO gap of beta orbitals: ',f12.6,' a.u.',f12.6,' eV')") gapeneb,gapeneb*au2eV
				end if
			else if (wfntype==2) then
				write(*,"(' Index of SOMO orbitals:',10i6)") (i,i=nint(nbelec+1),nint(naelec))
			end if
		end if
		if (ifiletype==7.or.ifiletype==8) then !cube file
			if (isilent==0) call drawisosurgui(1)
		else
			if (isilent==0) call drawmolgui
		end if


	!!!-------------------------------------------------
	!1!-------------------- Output properties at a point
	else if (isel==1) then
		call study0dim


	!!!--------------------------------------
	!2!-------------------- Topology analysis
	else if (isel==2) then
		call topo_main


	!!!--------------------------------------------
	!3!-------------------- Draw property in a line
	else if (isel==3) then
		call study1dim


	!!!-------------------------------------
	!4!-------------------- Draw plane graph
	else if (isel==4) then
		call study2dim

	!!!--------------------------------------------------------
	!5!------------------- Calculate, show and output grid file
	else if (isel==5) then
		call study3dim

	!!!---------------------------------------
	!6!!------------------- Check & Modify wavefunction or show GTF/Orbital information
	else if (isel==6) then
		call modwfn


	!!!---------------------------------------
	!7!!------------------- Population analysis
	else if (isel==7) then
		call population_main


	!!!---------------------------------------
	!8!!------------------- Orbital composition analysis
	else if (isel==8) then
		call orbcomp_main


	!!!---------------------------------------
	!9!!------------------- Bond order analysis
	else if (isel==9) then
		call bondorder_main


	!!!---------------------------------------
	!10!!------------------- Plot DOS
	else if (isel==10) then
		call DOS
		
	!!!---------------------------------------
	!11!!------------------- Plot spectrums
	else if (isel==11) then
		call plotspectrum


	!!!---------------------------------------
	!12!!------------------- Molecular surface analysis
	else if (isel==12) then
		call surfana

		
	!!!---------------------------------------
	!13!!------------------- Process grid data
	else if (isel==13) then
		call procgriddata


	!!!---------------------------------------
	!14!!------------------- Adaptive natural density partitioning (AdNDP)
	else if (isel==14) then
		call AdNDP
		
		
	!!!---------------------------------------
	!15!!------------------- Integrate fuzzy atomic space
	else if (isel==15) then
		call intatomspace(0)
	else if (isel==-15) then
		call fuzzySBL	


	!!!---------------------------------------
	!16!!------------------- Charge decomposition analysis
	else if (isel==16) then
		call CDA


	!!!---------------------------------------
	!17!!------------------- Basin integration
	else if (isel==17) then
		call basinana


	!!!---------------------------------------
	!18!!------------------- Electron excitation analysis
	else if (isel==18) then
		call excittrans_main


	!!!---------------------------------------
	!19!!------------------- Orbital localization analysis
	else if (isel==19) then
		call orbloc
		
		
	!!!---------------------------------------
	!20!!------------------- Visual study of weak interaction
	else if (isel==20) then
		call visweak_main
		
		
	!!!---------------------------------------
	!21!!------------------- Energy decomposition analysis
	else if (isel==21) then
		call EDA_main
		

	!!!---------------------------------------
	!100!!------------------- Misc and some unimportant functions, Part 1
	else if (isel==100) then
		call otherfunc_main
		
		
	!!!---------------------------------------
	!200!!------------------- Misc and some unimportant functions, Part 2
	else if (isel==200) then
		call otherfunc2_main


	!!!---------------------------------------
	!1000!!------------------- Special functions
	else if (isel==1000) then
		write(*,*)
		write(*,*) "0 Return to main menu"
		write(*,"(a,3f12.6)") " 1 Set reference point, current(Bohr):",refx,refy,refz
		write(*,"(a,i6)") " 2 Set iuserfunc, current:",iuserfunc
		write(*,"(a,i6)") " 3 Set iskipnuc, current:",iskipnuc
		if (pleA==0D0.and.pleB==0D0.and.pleC==0D0.and.pleD==0D0) then
			write(*,"(a)") " 4 Set the plane for user-defined function 38 (Not defined)"
		else
			write(*,"(a)") " 4 Set the plane for user-defined function 38 (Defined)"
		end if
		write(*,"(a,1PE18.8)") " 5 Set global temporary variable, current:",globaltmp
		write(*,"(a,i3)") " 10 Set the number of threads, current:",nthreads
		write(*,*) "11 Reload settings.ini"
        write(*,*) "12 Add a Bq atom to specific position"
		write(*,*) "90 Calculate nuclear attractive energy between a fragment and an orbital"
		write(*,*) "91 Exchange orbital energies and occupations"
		write(*,*) "92 Calculate result of various kinetic energy functionals"
		write(*,*) "97 Generate natural orbitals based on density matrix outputted by MRCC program"
		write(*,*) "99 Show EDF information (if any)"
		write(*,*) "100 Check the sanity of present wavefunction"
		read(*,*) i
		if (i==1) then
			write(*,*) "Input x,y,z in Bohr, e.g. 3.0,0.0,1.3"
			read(*,*) refx,refy,refz
			write(*,*) "Done!"
		else if (i==2) then
			write(*,*) "Input an integer, e.g. 24"
			read(*,*) iuserfunc
			write(*,*) "Done!"
		else if (i==3) then
			write(*,*) "Input the index of the nucleus, e.g. 24"
			read(*,*) iskipnuc
			write(*,*) "Done!"
		else if (i==4) then
			write(*,*) "1 Input index of three atoms to define the plane"
			write(*,*) "2 Input XYZ coordinate of three points to define the plane"
			read(*,*) iseldef
			if (iseldef==1) then
				write(*,*) "Input three indices, e.g. 2,4,5"
				read(*,*) i1,i2,i3
				call pointABCD(a(i1)%x,a(i1)%y,a(i1)%z,a(i2)%x,a(i2)%y,a(i2)%z,a(i3)%x,a(i3)%y,a(i3)%z,pleA,pleB,pleC,pleD)
			else if (iseldef==2) then
				write(*,*) "Input coordinate for point 1 (in Bohr), e.g. 1.0,-0.2,0.3"
				read(*,*) xtmp1,ytmp1,ztmp1
				write(*,*) "Input coordinate for point 2 (in Bohr), e.g. 2.0,-0.3,0.1"
				read(*,*) xtmp2,ytmp2,ztmp2
				write(*,*) "Input coordinate for point 3 (in Bohr), e.g. 1.3,-1.2,0.33"
				read(*,*) xtmp3,ytmp3,ztmp3
				call pointABCD(xtmp1,ytmp1,ztmp1,xtmp2,ytmp2,ztmp2,xtmp3,ytmp3,ztmp3,pleA,pleB,pleC,pleD)
			end if
			tmpval=dsqrt(pleA**2+pleB**2+pleC**2)
			write(*,"(' The unit vector normal to the plane is:',3f10.5)") pleA/tmpval,pleB/tmpval,pleC/tmpval
		else if (i==5) then
			write(*,*) "Input the value"
			read(*,*) globaltmp
		else if (i==10) then
			write(*,*) "Input an integer, e.g. 8"
			read(*,*) nthreads
			write(*,*) "Done!"
		else if (i==11) then
			call loadsetting
			write(*,*) "Done!"
		else if (i==12) then
            do while(.true.)
                write(*,*) "Write the X,Y,Z of the Bq atom to be added in Bohr, e.g. 0.2,0,-3.5"
                write(*,*) "Input ""q"" can exit"
                read(*,"(a)") c200tmp
                if (c200tmp=="q") then
                    exit
                else
                    read(c200tmp,*) tmpx,tmpy,tmpz
                    call addbq(tmpx,tmpy,tmpz)
			        write(*,*) "Done!"
                end if
            end do
		else if (i==90) then
			call attene_orb_fragnuc
		else if (i==91) then
			do iorb=1,nmo
				tmp=MOocc(iorb)
				MOocc(iorb)=MOene(iorb)
				MOene(iorb)=tmp
			end do
			imodwfn=1
			write(*,*) "Done!"
			if (allocated(CObasa)) then
				write(*,*) "Updating density matrix..."
				call genP
				write(*,*) "Density matrix has been updated"
			end if
		else if (i==92) then
			call intKED
		else if (i==97) then
			call MRCC_gennatorb
		else if (i==99) then
			if (.not.allocated(b_EDF)) then
				write(*,*) "EDF field was not loaded"
			else
				write(*,"( ' The number of inner-core electrons represented by EDF:',i6)") nEDFelec
				write(*,*) "Information of EDF primitives:"
				write(*,*) "Column 1: Index"
				write(*,*) "Column 2: Atom"
				write(*,*) "Column 3: Function type"
				write(*,*) "Column 4: Exponent"
				write(*,*) "Column 5: Coefficient"
				do iEDFprim=1,nEDFprims
					write(*,"(3i6,2f20.8)") iEDFprim,b_EDF(iEDFprim)%center,b_EDF(iEDFprim)%type,b_EDF(iEDFprim)%exp,CO_EDF(iEDFprim)
				end do
			end if
		else if (i==100) then
			call wfnsanity
		end if
	end if

end do !End main cycle

end program