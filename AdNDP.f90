!! --------------- Perform Adaptive natural density partitioning
subroutine AdNDP
use defvar
use util
use GUI
implicit real*8 (a-h,o-z)
integer,allocatable :: NAOinit(:),NAOend(:) !NAO index range of each atom
integer,allocatable :: nNAOatm(:) !The number of NAOs of each atom
integer,allocatable :: NAOcen(:),NAOtype(:) !The center attributed to and type of NAOs, 0=Cor 1=Val 2=Ryd
integer,allocatable :: atmcomb(:) !Store combination of specific number of atoms
integer,allocatable :: idxarray(:) !A contiguous array by default, used as underground numbering array for generating atom combinations
integer,allocatable :: searchlist(:) !Store atom indices for those will be exhaustively searched
real*8,allocatable :: DMNAO(:,:),DMNAObeta(:,:),orbeigval(:),orbeigvec(:,:),removemat(:,:),colvec(:,:),rowvec(:,:),DMNAOblk(:,:),AONAO(:,:)
! real*8 :: bndcrit(30)=(/ 1.9D0,1.7D0,1.7D0,(1.8D0,i=4,30) /) !Bond threshold for different center-bonds
real*8 :: bndcrit=1.7D0
real*8,allocatable :: candiocc(:),candivec(:,:),candinatm(:) !Store candidate orbital information, occupation, eigenvector(in total NAOs), number of atoms
integer,allocatable :: candiatmlist(:,:) !Store atom list of candidate orbitals
real*8,allocatable :: savedocc(:),savedvec(:,:),savednatm(:) !Store saved orbital information, occupation, eigenvector(in total NAOs), number of atoms
integer,allocatable :: savedatmlist(:,:) !Store atom list of saved orbitals
real*8,allocatable :: oldsavedocc(:),oldsavedvec(:,:),oldsavednatm(:),oldDMNAO(:,:) !For temporarily store data
integer,allocatable :: oldsavedatmlist(:,:),eiguselist(:),tmparr(:)
integer numNAO !Total number of NAOs
real*8,allocatable :: adndpcobas(:,:),Fmat(:,:),Emat(:,:)
character :: c80tmp*80,c80tmp2*80,c200tmp*200,c1000tmp*1000,c2000tmp*2000,selectyn,fchfilename*200=' '

open(10,file=filename,status="old")
!Read in NAO range for all atoms
call loclabel(10,"NATURAL POPULATIONS",ifound)
if (ifound==0) then
	write(*,*) "Error: Cannot find NATURAL POPULATIONS field in the input file!"
	write(*,*) "Press ENTER button to return"
	read(*,*)
	return
end if
write(*,*) "Loading NAO information and density matrix in NAO basis..."
read(10,*)
read(10,*)
read(10,*)
read(10,*)
ilastspc=0
!We need to know how many atoms in total
do while(.true.)
	read(10,"(a)") c80tmp
	if (c80tmp==' '.or.index(c80tmp,"low occupancy")/=0.or.index(c80tmp,"Population inversion found")/=0.or.index(c80tmp,"effective core potential")/=0) then
		if (ilastspc==1) then
			ncenter=iatm
			numNAO=inao
			exit
		end if
		ilastspc=1 !last line is space
	else
		read(c80tmp,*) inao,c80tmp2,iatm
		ilastspc=0
	end if
end do
write(*,"(' Number of atoms:',i5)") ncenter
if (.not.allocated(a)) allocate(a(ncenter))
allocate(NAOinit(ncenter),NAOend(ncenter))
allocate(NAOcen(numNAO),NAOtype(numNAO),nNAOatm(ncenter))
call loclabel(10,"NATURAL POPULATIONS",ifound,1)
read(10,*)
read(10,*)
read(10,*)
read(10,*)
ilastspc=1
do while(.true.)
	read(10,"(a)") c80tmp
	if (c80tmp/=' ') then
		read(c80tmp,*) inao,c80tmp2,iatm
		do iele=1,nelesupp
			if (c80tmp2(1:2)==ind2name(iele)) then
				a(iatm)%name=c80tmp2(1:2)
				a(iatm)%index=iele
				exit
			end if
			if (iele==nelesupp) write(*,*) "Warning: Detected unrecognizable element name!"
		end do
		NAOcen(inao)=iatm
		if (index(c80tmp,"Cor")/=0) then
			NAOtype(inao)=0
		else if (index(c80tmp,"Val")/=0) then
			NAOtype(inao)=1
		else if (index(c80tmp,"Ryd")/=0) then
			NAOtype(inao)=2
		end if
		if (ilastspc==1) NAOinit(iatm)=inao
		ilastspc=0
	else
		NAOend(iatm)=inao
		if (iatm==ncenter) exit
		ilastspc=1
	end if
end do
do idx=1,ncenter
	nNAOatm(idx)=NAOend(idx)-NAOinit(idx)+1
end do
write(*,"(' Number of natural atomic orbitals (NAOs):',i6)") numNAO

call loclabel(10,'basis functions,',igauout)
if (igauout==1) then !Gaussian+NBO output file
	read(10,*) nbasis
	write(*,"(' The number of basis functions:',i6)") nbasis
else !Assume that the number of basis functions is identical to numNAO. However, when this is not true, cumbersome thing will occur...
	nbasis=numNAO
end if

!Read in density matrix in NAO basis. NAO information always use those generated by total density
!DMNAO and AONAO is different for total, alpha and beta density
allocate(DMNAO(numNAO,numNAO))
call loclabel(10,"NAO density matrix:",ifound)
if (ifound==0) then
	write(*,*) "Error: Cannot found NAO density matrix field in the input file"
	return
end if
!Check format before reading, NBO6 use different format to NBO3
!For open-shell case, DMNAO doesn't print for total, so the first time loaded DMNAO is alpha(open-shell) or total(closed-shell)
read(10,"(a)") c80tmp
backspace(10)
nskipcol=16 !NBO3
if (c80tmp(2:2)==" ") nskipcol=17 !NBO6
call readmatgau(10,DMNAO,0,"f8.4 ",nskipcol,8,3)
iusespin=0
!Check if this is open-shell calculation
call loclabel(10," Alpha spin orbitals ",iopenshell)
if (iopenshell==1) then
	write(*,*) "Use which density matrix? 0=Total 1=Alpha 2=Beta"
	read(*,*) iusespin
	if (iusespin==1.or.iusespin==2) bndcrit=bndcrit/2D0
	if (iusespin==0.or.iusespin==2) then !if ==1, that is alpha, this is current DMNAO
		allocate(DMNAObeta(numNAO,numNAO))
		call loclabel(10,"*******         Beta  spin orbitals         *******",ifound)
		call loclabel(10,"NAO density matrix:",ifound,0)
		call readmatgau(10,DMNAObeta,0,"f8.4 ",nskipcol,8,3)
		if (iusespin==0) then
			DMNAO=DMNAO+DMNAObeta
		else if (iusespin==2) then
			DMNAO=DMNAObeta
		end if
		deallocate(DMNAObeta)
	end if
end if

close(10) !Loading finished


!==== Remove core contribution from density matrix
do i=1,numNAO
	if (NAOtype(i)==0) DMNAO(i,i)=0D0
end do
write(*,*) "Note: Contributions from core NAOs to density matrix have been eliminated"
write(*,*) "Note: Default exhaustive search list is the entire system"
write(*,*)
!Initialization
nlencandi=100*ncenter !This is absolutely enough for each number of center searching
allocate(candiocc(nlencandi+1),candivec(nlencandi+1,numNAO),candiatmlist(nlencandi+1,ncenter),candinatm(nlencandi+1)) !The last element is used as temporary space to exchange information
allocate(eiguselist(nlencandi))
nlensaved=30*ncenter !Each atom can form at most four bond, but we leave more space
allocate(savedocc(nlensaved),savedvec(nlensaved,numNAO),savedatmlist(nlensaved,ncenter),savednatm(nlensaved))
ncenana=1
ioutdetail=0
numsaved=0 !Number of saved orbitals
numcandi=0 !Number of candidate orbitals
lensearchlist=ncenter !The list length of atom search range, default is entire system
allocate(colvec(numNAO,1),rowvec(1,numNAO))
allocate(atmcomb(ncenter),idxarray(ncenter),searchlist(ncenter)) !Note: Effective number of elements in searchlist is lensearchlist
forall (i=1:ncenter) searchlist(i)=i

isel=0
write(*,*) "      ======== Adaptive natural density partitioning (AdNDP) ========"
do while(.true.)
1	if (isel/=5.and.isel/=13.and.isel/=16) then
		!Sort candidate orbitals according to occupation varies from large to small and then print out them
		do i=1,numcandi
			do j=1,numcandi
				if (candiocc(i)>candiocc(j)) then !Exchange candidate orbital i and j, nlencandi+1 is used as temporary slot for exchanging, candinatm is needn't to be exchanged since they are the same
					candiocc(nlencandi+1)=candiocc(i)
					candivec(nlencandi+1,:)=candivec(i,:)
					candiatmlist(nlencandi+1,:)=candiatmlist(i,:)
					candiocc(i)=candiocc(j)
					candivec(i,:)=candivec(j,:)
					candiatmlist(i,:)=candiatmlist(j,:)
					candiocc(j)=candiocc(nlencandi+1)
					candivec(j,:)=candivec(nlencandi+1,:)
					candiatmlist(j,:)=candiatmlist(nlencandi+1,:)
				end if
			end do
		end do
		if (numcandi>0) then
			write(*,*) "  ---- Current candidate orbital list, sorted according to occupation ----"
			if (numcandi>50) write(*,*) "Note: Only the 50 orbitals with highest occupancy are listed"
			do icandi=min(50,numcandi),1,-1 !Print from occupation of small to large, so index is decreased
				write(*,"(' #',i4,' Occ:',f7.4,' Atom:',9(i4,a))") icandi,candiocc(icandi),(candiatmlist(icandi,ii),a(candiatmlist(icandi,ii))%name,ii=1,candinatm(icandi))
			end do
			write(*,*)
 		else
 			write(*,*) "Note: Candidate orbital list is empty currently"
		end if
	end if

	!Check total number of electrons
	remainelec=0D0
	do iatm=1,lensearchlist
		do iNAO=NAOinit(searchlist(iatm)),NAOend(searchlist(iatm))
			remainelec=remainelec+DMNAO(iNAO,iNAO)
		end do
	end do
	write(*,"(' Residual valence electrons of all atoms in the search list:',f12.6)") remainelec

	write(*,*) "-10 Return to main menu"
	if (ioutdetail==1) write(*,*) "-2 Switch if output detail of exhaustive searching process, current: Yes"
	if (ioutdetail==0) write(*,*) "-2 Switch if output detail of exhaustive searching process, current: No"
	write(*,*) "-1 Define exhaustive search list"
	if (numcandi>0) write(*,*) "0 Pick out some candidate orbitals and update occupations of others"
	write(*,"(' 1 Perform orbitals search for a specific atom combination')")
	write(*,"(' 2 Perform exhaustive search of ',i2,'-centers orbitals within the search list')") ncenana
	write(*,*) "3 Set the number of centers in the next exhaustive search"
	write(*,"(a,f8.3)") " 4 Set occupation threshold in the next exhaustive search, current:",bndcrit
	if (numsaved>0) write(*,"(' 5 Show information of all AdNDP orbitals, current number:',i5)") numsaved
	if (numsaved>0) write(*,*) "6 Delete some AdNDP orbitals"
	if (numsaved>0) write(*,*) "7 Visualize AdNDP orbitals and molecular geometry"
	if (numsaved==0) write(*,*) "7 Visualize AdNDP orbitals (none) and molecular geometry"
	if (numcandi>0) write(*,*) "8 Visualize candidate orbitals and molecular geometry"
	if (numcandi==0) write(*,*) "8 Visualize candidate orbitals (none) and molecular geometry"
	if (numsaved>0) write(*,*) "9 Export some AdNDP orbitals to Gaussian type cube files"
	if (numcandi>0) write(*,"(a)") " 10 Export some candidate orbitals to Gaussian type cube files"
	if (allocated(oldDMNAO)) write(*,"(a)") " 11 Save current density matrix and AdNDP orbital list again"
	if (.not.allocated(oldDMNAO)) write(*,"(a)") " 11 Save current density matrix and AdNDP orbital list (Unsaved)"
	if (allocated(oldDMNAO)) write(*,"(a)") " 12 Load saved density matrix and AdNDP orbital list"
	write(*,"(a)") " 13 Show residual density distributions on the atoms in the search list"
	if (numsaved>0) write(*,"(a)") " 14 Output all AdNDP orbitals as .molden file"
! 	write(*,"(a)") "15 Output current density matrix to DMNAO.txt in current folder" !Rarely used, screen it to cut down list length
	write(*,"(a)") " 16 Output energy of picked AdNDP orbitals"
	read(*,*) isel
	
	
	if (isel==-10) then
		return
	else if (isel==-2) then
		if (ioutdetail==1) then
			ioutdetail=0
		else
			ioutdetail=1
		end if
	else if (isel==-1) then
		call adndpdeflist(searchlist,lensearchlist)
	else if (isel==0) then
		write(*,*) "Input the index range of the candidate orbitals to be picked out, e.g. 1,4"
		write(*,"(a)") " Note: If only input one number (N), then N orbitals with the largest occupations will be picked out"
		read(*,"(a)") c80tmp
		if (index(c80tmp,',')/=0) then !Inputted two numbers
			read(c80tmp,*) ilow,ihigh
		else if (c80tmp==" ".or.index(c80tmp,'-')/=0) then
			write(*,*) "Error: Unknown command"
			cycle
		else
			ilow=1
			read(c80tmp,*) ihigh
		end if
		npickout=ihigh-ilow+1
		if (ihigh>numcandi) then
			write(*,*) "Error: Picked orbitals should not be larger than candidate orbitals!"
			goto 1
		end if
		!Pick some orbitals from candidate list to permanent list
		do i=ilow,ihigh
			iaug=i-ilow+1
			savedocc(numsaved+iaug)=candiocc(i)
			savedvec(numsaved+iaug,:)=candivec(i,:)
			savedatmlist(numsaved+iaug,:)=candiatmlist(i,:)
			savednatm(numsaved+iaug)=candinatm(i)
			!Deplete the density of the picked orbitals from DMNAO
			colvec(:,1)=candivec(i,:)
			rowvec(1,:)=candivec(i,:)
			DMNAO=DMNAO-candiocc(i)*matmul(colvec,rowvec)
		end do
		numsaved=numsaved+npickout
		!Shift candidate list to fill the gap
		newnumcandi=numcandi-npickout
		if (numcandi>=ihigh+1) then
			candiocc(ilow:newnumcandi)=candiocc(ihigh+1:numcandi)
			candivec(ilow:newnumcandi,:)=candivec(ihigh+1:numcandi,:)
			candiatmlist(ilow:newnumcandi,:)=candiatmlist(ihigh+1:numcandi,:)
			candinatm(ilow:newnumcandi)=candinatm(ihigh+1:numcandi)
		end if
		numcandi=newnumcandi
		!Recalculate eigenval and eigenvec of remained candidate orbitals
		!Since an atom combination may have many orbitals exceed threshold, we first specify which eigenvalue of each combination will be used. If the combination is unique, then the largest one will be used
		nlenlist=candinatm(1) !The same to other candidate orbitals
		eiguselist(:)=0 !iwhichuse=n means the nth largest eigenvalue/eigenvector in this atom combination will be used. 0 means hasn't specified
		do icandi=1,numcandi
			iseleig=1
			if (eiguselist(icandi)/=0) cycle !Already specified
			do jcandi=1,numcandi
				if (all(candiatmlist(jcandi,1:nlenlist)==candiatmlist(icandi,1:nlenlist))) then
					eiguselist(jcandi)=iseleig
					iseleig=iseleig+1
				end if
			end do
		end do
		
		do icandi=1,numcandi
			nNAOblk=sum(nNAOatm(candiatmlist(icandi,1:candinatm(icandi)))) !Number of NAOs in current DMNAO block
			allocate(DMNAOblk(nNAOblk,nNAOblk),orbeigval(nNAOblk),orbeigvec(nNAOblk,nNAOblk))
			!Construct density matrix block
			irowed=0
			do idx1=1,candinatm(icandi) !Scan rows
				iatm=candiatmlist(icandi,idx1)
				irowbg=irowed+1
				irowed=irowbg+nNAOatm(iatm)-1
				icoled=0
				do idx2=1,candinatm(icandi) !Scan columns
					jatm=candiatmlist(icandi,idx2)
					icolbg=icoled+1
					icoled=icolbg+nNAOatm(jatm)-1
					DMNAOblk(irowbg:irowed,icolbg:icoled)=DMNAO(NAOinit(iatm):NAOend(iatm),NAOinit(jatm):NAOend(jatm))
				end do
			end do
			!Diagonalize the block
			call diagsymat(DMNAOblk,orbeigvec,orbeigval,istat)
			if (istat/=0) write(*,*) "Error: Diagonalization failed!"
			!Update candidate orbital
			ieiguse=nNAOblk-eiguselist(icandi)+1
			candiocc(icandi)=orbeigval(ieiguse) !The last element, namely nNAOblk, correspond to the largest occupation element
			candivec(icandi,:)=0D0 !Clean
			ied=0
			do idx=1,candinatm(icandi)
				iatm=candiatmlist(icandi,idx)
				ibg=ied+1
				ied=ibg+nNAOatm(iatm)-1
				candivec(icandi,NAOinit(iatm):NAOend(iatm))=orbeigvec(ibg:ied,ieiguse)
			end do
			deallocate(DMNAOblk,orbeigval,orbeigvec)
		end do
		write(*,"(i4,' candidate orbitals remain')") numcandi
		
	else if (isel==1.or.isel==2) then
		if (isel==1) then
			write(*,*) "Input atom indices, e.g. 3,4,6,7,12   (should less than 1000 characters)"
			write(*,*) "Note: Input ""all"" means all atoms in present system will be chosen"
			read(*,"(a)") c1000tmp
			if (index(c1000tmp,"all")/=0) then
				ncenana=ncenter
				forall(i=1:ncenter) atmcomb(i)=i
			else
				ncenana=1
				do i=1,len_trim(c1000tmp)
					if (c1000tmp(i:i)==',') ncenana=ncenana+1
				end do
				read(c1000tmp,*) atmcomb(1:ncenana)
				if (any(atmcomb(1:ncenana)>ncenter).or.any(atmcomb(1:ncenana)<=0)) then
					write(*,*) "Error: Some inputted atom indices exceeded valid range!"
					goto 1
				end if
			end if
		else if (isel==2) then
			forall (i=1:ncenana) idxarray(i)=i !Used as underground numbering index during generating combination
			atmcomb(1:ncenana)=searchlist(idxarray(1:ncenana))
			write(*,"(' Exhaustively searching ',i2,'-center orbitals, please wait...')") ncenana
		end if
		ipos=ncenana !Current position in the array
		numcandi=0 !Clean current candidate list
		ntotcomb=0 !Number of tried
		ioutcomb=1 !If do analysis for present combination
		cyccomb: do while(ipos>0)
			if (ioutcomb==1) then
				ntotcomb=ntotcomb+1
				!============Analyze atom combination in this time
				if (ioutdetail==1) write(*,"(' Searching atom',12i5)") atmcomb(1:ncenana)
				nNAOblk=sum(nNAOatm(atmcomb(1:ncenana))) !Number of NAOs in current DMNAO block
				allocate(DMNAOblk(nNAOblk,nNAOblk),orbeigval(nNAOblk),orbeigvec(nNAOblk,nNAOblk))
				!Construct density matrix block
				irowed=0
				do idx1=1,ncenana !Scan rows
					iatm=atmcomb(idx1)
					irowbg=irowed+1
					irowed=irowbg+nNAOatm(iatm)-1
					icoled=0
					do idx2=1,ncenana !Scan columns
						jatm=atmcomb(idx2)
						icolbg=icoled+1
						icoled=icolbg+nNAOatm(jatm)-1
						DMNAOblk(irowbg:irowed,icolbg:icoled)=DMNAO(NAOinit(iatm):NAOend(iatm),NAOinit(jatm):NAOend(jatm))
					end do
				end do
				!Diagonalize the block
				call diagsymat(DMNAOblk,orbeigvec,orbeigval,istat)
				if (istat/=0) write(*,*) "Error: Diagonalization failed!"
				if (isel==2.and.ioutdetail==1) then
					write(*,*) "Eigenvalues:"
					write(*,"(10f7.4)") orbeigval
				end if
				!Analyze result at this time
				do iNAO=nNAOblk,1,-1 !orbeigval varies from small to large, so cycle from large to small
					if (orbeigval(iNAO)>bndcrit.or.isel==1) then !When user specified combination, all orbitals will be outputted
						numcandi=numcandi+1
						if (isel==2.and.ioutdetail==1) write(*,"('Found the ',i4,'th candidate orbital with occupation:',f8.4)") numcandi,orbeigval(iNAO)
						if (numcandi>nlencandi) then
							write(*,"(a)") " Error: Candidate orbital list is overflow! You may need to increase variable ""nlencandi"" in AdNDP.f90 or properly tight up occupation threshold"
							write(*,*) "Press ENTER button to continue"
							read(*,*)
							deallocate(DMNAOblk,orbeigval,orbeigvec)
							numcandi=numcandi-1
							exit cyccomb
						end if
						!Move this orbital to candidate list
						candiocc(numcandi)=orbeigval(iNAO)
						candiatmlist(numcandi,1:ncenana)=atmcomb(1:ncenana)
						candinatm(numcandi)=ncenana
						candivec(numcandi,:)=0D0 !Clean
						ied=0
						do idx=1,ncenana
							iatm=atmcomb(idx)
							ibg=ied+1
							ied=ibg+nNAOatm(iatm)-1
							candivec(numcandi,NAOinit(iatm):NAOend(iatm))=orbeigvec(ibg:ied,iNAO)
						end do
					else
						exit
					end if
				end do
				deallocate(DMNAOblk,orbeigval,orbeigvec)
				if (ioutdetail==1) write(*,*)
				!============End analyze this combination
			end if
			if (isel==1) exit !isel==1 only do once for user inputted combination
			
			ioutcomb=0
			idxarray(ipos)=idxarray(ipos)+1
			if (idxarray(ipos)>lensearchlist) then
				ipos=ipos-1 !Go back to last position
				cycle
			end if
			if (ipos<ncenana) then
				ipos=ipos+1
				idxarray(ipos)=idxarray(ipos-1)
				cycle
			end if
			if (ipos==ncenana) then
				ioutcomb=1
				atmcomb(1:ncenana)=searchlist(idxarray(1:ncenana))
			end if
		end do cyccomb
		
		if (isel==2) write(*,"(' Tried',i9,' combinations, totally found',i9,' candidate orbitals',/)") ntotcomb,numcandi
		if (ncenana<lensearchlist.and.isel==2) ncenana=ncenana+1
	else if (isel==3) then
		write(*,"(a,i6)") " Input a number, should between 1 and",lensearchlist
		read(*,*) ncenanatmp
		if (ncenanatmp>lensearchlist) then
			write(*,*) "Error: The number of centers to be searched exceeds valid range!"
			goto 1
		end if
		ncenana=ncenanatmp
	else if (isel==4) then
		write(*,*) "Input a number, e.g. 1.9"
		read(*,*) bndcrit
	else if (isel==5) then
		write(*,*) "                         ---- AdNDP orbital list ----"
		do i=1,numsaved
			write(*,"(' #',i5,' Occ:',f8.4,' Atom:',9(i4,a))") i,savedocc(i),(savedatmlist(i,ii),a(savedatmlist(i,ii))%name,ii=1,savednatm(i))
		end do
		write(*,"(' Total occupation number in above orbitals:',f10.4,/)") sum(savedocc(1:numsaved))
	else if (isel==6) then
		write(*,*) "Input orbital index range that will be removed, e.g. 7,10"
		write(*,*) "Note: The density of these orbitals will not be returned to density matrix"
		read(*,*) ilow,ihigh
		if (ihigh<=numsaved) then
			numback=numsaved-ihigh
			savedocc(ilow:ilow+numback-1)=savedocc(ihigh+1:numsaved)
			savedvec(ilow:ilow+numback-1,:)=savedvec(ihigh+1:numsaved,:)
			savedatmlist(ilow:ilow+numback-1,:)=savedatmlist(ihigh+1:numsaved,:)
			savednatm(ilow:ilow+numback-1)=savednatm(ihigh+1:numsaved)
			numsaved=numsaved-(ihigh-ilow+1)
		else
			write(*,*) "Error: Index exceeded valid range"
		end if
		
	else if (isel==7.or.isel==8.or.isel==9.or.isel==10.or.isel==14) then !Visualize or export cube file for candidate or saved orbitals, or save them as .molden
		!Now we need basis functions information, load them from .fch file
		!If .fch or .fchk file with identical name in identical folder as initial input file can be found, then directly load it
		lenname=len_trim(filename)
		inquire(file=filename(1:lenname-3)//'fch',exist=alive)
		if (alive) then
			fchfilename=filename(1:lenname-3)//'fch'
		else
			inquire(file=filename(1:lenname-3)//'fchk',exist=alive)
			if (alive) fchfilename=filename(1:lenname-3)//'fchk'
		end if
		if (fchfilename==' ') then
			write(*,*) "Input path of corresponding .fch file, e.g. C:\test.fch"
			read(*,"(a)") fchfilename
			inquire(file=fchfilename,exist=alive)
			if (alive.eqv..false.) then
				write(*,*) "Error: File cannot be found! Hence orbitals can not be visualized"
				write(*,*)
				fchfilename=' '
				goto 1
			end if
		end if
		if (.not.allocated(AONAO)) then
			allocate(AONAO(nbasis,numNAO))
			call loadAONAO(AONAO,numNAO,ifound)
			if (ifound==0) cycle
		end if
		!Load mainbody of .fch file, and convert adndp orbitals (NAO basis) to CO matrix (GTF basis) so that fmo function can directly calculate orbital wavefunction value
		write(*,"(' Loading ',a)") trim(fchfilename)
		ifixorbsign=1 !Automatically fix sign of the isosurfaces generated by drawmolgui
        
		if (isel==7) then !Visualize saved orbitals
			allocate(adndpcobas(nbasis,numsaved))
			adndpcobas(:,:)=matmul(AONAO,transpose(savedvec)) !cobasaadndp(i,j) means coefficient of basis function i in orbital j
			call readfchadndp(fchfilename,iusespin,savedocc,adndpcobas,numsaved)
			call drawmolgui
            
		else if (isel==8) then !Visualize candidate orbitals
			allocate(adndpcobas(nbasis,numcandi))
			adndpcobas(:,:)=matmul(AONAO,transpose(candivec))
			call readfchadndp(fchfilename,iusespin,candiocc,adndpcobas,numcandi)
			call drawmolgui
            
		else if (isel==14) then !Output all saved AdNDP orbitals as .molden file
			call dealloall
			call readfch(fchfilename,1)
			wfntype=3
			CObasa=0
			MOocc=0
			MOene=0
			CObasa(:,1:numsaved)=matmul(AONAO,transpose(savedvec))
			MOocc(1:numsaved)=(savedocc(1:numsaved))
			nmo=nbasis !AdNDP only performed for total density or single set of spin spin, therefore when nmo should be forced to equal to nbasis
			call outmolden("AdNDP.molden",10)
			write(*,*) "All AdNDP orbitals have been stored to AdNDP.molden in current folder"
			write(*,*)
            
		else if (isel==9.or.isel==10) then !Export saved or candidate AdNDP orbitals as cube file
			if (isel==9) then !Saved orbitals
				allocate(adndpcobas(nbasis,numsaved))
				adndpcobas(:,:)=matmul(AONAO,transpose(savedvec)) !cobasaadndp(i,j) means coefficient of basis function i in orbital j
				call readfchadndp(fchfilename,iusespin,savedocc,adndpcobas,numsaved)
			else if (isel==10) then !Candidate orbitals
				allocate(adndpcobas(nbasis,numcandi))
				adndpcobas(:,:)=matmul(AONAO,transpose(candivec))
				call readfchadndp(fchfilename,iusespin,candiocc,adndpcobas,numcandi)
			end if
			!Set up grid
            call setgrid(0,igridsel)
			if (allocated(cubmat)) deallocate(cubmat)
			allocate(cubmat(nx,ny,nz))
				
			if (isel==9) then !Export saved AdNDP orbitals
                write(*,*)
				write(*,*) "Input index range of AdNDP orbitals to be exported"
                write(*,*) "e.g. 1-3,8,10-12 corresponds to 1,2,3,8,10,11,12"
                do while(.true.)
                    read(*,"(a)") c2000tmp
                    call str2arr(c2000tmp,ntmp)
                    allocate(tmparr(ntmp))
                    call str2arr(c2000tmp,ntmp,tmparr)
				    if (any(tmparr>numsaved)) then
					    write(*,*) "Error: Inputted index exceeded valid range! Input again"
					    deallocate(tmparr)
					else
                        exit
				    end if
                end do
				do itmp=1,ntmp
                    iorb=tmparr(itmp)
                    write(*,"(' Calculating grid data for orbital',i6,', please wait...')") iorb
					call savecubmat(4,1,iorb)
					if (sum(cubmat)<0) cubmat=-cubmat
					write(c80tmp,"('AdNDPorb',i4.4,'.cub')") iorb
					open(10,file=c80tmp,status="replace")
					call outcube(cubmat,nx,ny,nz,orgx,orgy,orgz,gridvec1,gridvec2,gridvec3,10)
					close(10)
					write(*,"(1x,a,' has been exported to current folder')") trim(c80tmp)
				end do
			else if (isel==10) then !Export candidate orbitals
                write(*,*)
				write(*,*) "Input index range of candidate orbitals to be exported"
                write(*,*) "e.g. 1-3,8,10-12 corresponds to 1,2,3,8,10,11,12"
                do while(.true.)
                    read(*,"(a)") c2000tmp
                    call str2arr(c2000tmp,ntmp)
                    allocate(tmparr(ntmp))
                    call str2arr(c2000tmp,ntmp,tmparr)
				    if (any(tmparr>numcandi)) then
					    write(*,*) "Error: Inputted index exceeded valid range! Input again"
					    deallocate(tmparr)
					else
                        exit
				    end if
                end do
				do itmp=1,ntmp
                    iorb=tmparr(itmp)
                    write(*,"(' Calculating grid data for orbital',i6,', please wait...')") iorb
					call savecubmat(4,1,iorb)
					if (sum(cubmat)<0) cubmat=-cubmat
					write(c80tmp,"('candiorb',i4.4,'.cub')") iorb
					open(10,file=c80tmp,status="replace")
					call outcube(cubmat,nx,ny,nz,orgx,orgy,orgz,gridvec1,gridvec2,gridvec3,10)
					close(10)
					write(*,"(1x,a,' has been exported to current folder')") trim(c80tmp)
				end do
			end if
			write(*,*)
			deallocate(cubmat,tmparr)
		end if
		if (allocated(adndpcobas)) deallocate(adndpcobas)
		
	else if (isel==11) then
		if (.not.allocated(oldDMNAO)) allocate(oldDMNAO(numNAO,numNAO))
		oldDMNAO=DMNAO
		if (allocated(oldsavedvec)) deallocate(oldsavedvec,oldsavedocc,oldsavedatmlist,oldsavednatm)
		allocate(oldsavedvec(numsaved,numNAO),oldsavedocc(numsaved),oldsavedatmlist(numsaved,ncenter),oldsavednatm(numsaved))
		oldsavedvec=savedvec(1:numsaved,:)
		oldsavedocc=savedocc(1:numsaved)
		oldsavedatmlist=savedatmlist(1:numsaved,:)
		oldsavednatm=savednatm(1:numsaved)
		noldorb=numsaved
		noldcenana=ncenana
		write(*,*) "Done, current density matrix in NAO basis and AdNDP orbital list has been saved"
        
	else if (isel==12) then
		if (.not.allocated(oldDMNAO)) then
			write(*,*) "Error: Density matrix in NAO basis has not been saved before!"
		else
			DMNAO=oldDMNAO
			numsaved=noldorb
			ncenana=noldcenana
			savedvec(1:numsaved,:)=oldsavedvec
			savedocc(1:numsaved)=oldsavedocc
			savedatmlist(1:numsaved,:)=oldsavedatmlist
			savednatm(1:numsaved)=oldsavednatm
			write(*,*) "Done, the saved density matrix in NAO basis and AdNDP orbital list has been recovered"
		end if
        
	else if (isel==13) then
		write(*,*) "Residual valence electrons on each atom in the search list:"
		do idx=1,lensearchlist
			iatm=searchlist(idx)
			residatmdens=0
			do iNAO=NAOinit(iatm),NAOend(iatm)
				residatmdens=residatmdens+DMNAO(iNAO,iNAO)
			end do
			write(*,"(i8,a,':',f8.4)",advance='no') iatm,a(iatm)%name,residatmdens
			if (mod(iatm,4)==0) write(*,*)
		end do
		write(*,*)
        
	else if (isel==15) then
		open(10,file="DMNAO.txt",status="old")
		call showmatgau(DMNAO,"Density matrix in NAO basis",0,"f12.6",10)
		close(10)
		write(*,*) "Done, density matrix in NAO basis has been saved to DMNAO.txt in current folder"
        
	else if (isel==16) then !Evaluate orbital energy
		if (numsaved==0) then
			write(*,*) "Error: You need to pick out at least one orbital!"
			write(*,*)
			cycle
		end if
		!Load Fock matrix in AOs
		if (.not.allocated(Fmat)) then
			write(*,"(a)") " Input the file recording Fock matrix in original basis functions in lower triangular form, e.g. C:\fock.txt"
			write(*,*) "Note: If the suffix is .47, the Fock matrix will be directly loaded from it"
			read(*,"(a)") c200tmp
			inquire(file=c200tmp,exist=alive)
			if (alive==.false.) then
				write(*,*) "Error: Unable to find this file!"
				cycle
			end if
			open(10,file=filename,status="old")
			call loclabel(10,"basis functions,",ifound)
			read(10,*) nbasis
			close(10)
			allocate(Fmat(nbasis,nbasis))
			open(10,file=c200tmp,status="old")
			if (index(c200tmp,".47")/=0) then
				call loclabel(10,"$FOCK",ifound)
				if (ifound==0) then
					write(*,*) "Error: Unable to find $FOCK field in this file!"
					close(10)
					cycle
				end if
				read(10,*)
				write(*,*) "Trying to load Fock matrix from .47 file..."
			end if
			read(10,*) ((Fmat(i,j),j=1,i),i=1,nbasis) !Load total or alpha Fock matrix
			if (iopenshell==1) then !Open-shell
				if (iusespin==0) then !User selected total density
					write(*,"(a,/)") " Error: This is an open-shell system but you selected analyzing total density, in this case orbital energy cannot be printed"
					cycle
				else if (iusespin==2) then !User selected beta spin
					read(10,*) ((Fmat(i,j),j=1,i),i=1,nbasis) !Load beta Fock matrix
				end if
			end if
			do i=1,nbasis !Fill upper triangular part
 				do j=i+1,nbasis
 					Fmat(i,j)=Fmat(j,i)
 				end do
			end do
		end if
		if (.not.allocated(AONAO)) then
			allocate(AONAO(nbasis,numNAO))
			call loadAONAO(AONAO,numNAO,ifound)
			if (ifound==0) cycle
		end if
		allocate(adndpcobas(nbasis,numsaved),Emat(numsaved,numsaved))
		!Note that savedvec is savedvec(numsaved,numNAO)
		adndpcobas=matmul(AONAO,transpose(savedvec(1:numsaved,:)))
		Emat=matmul(matmul(transpose(adndpcobas),Fmat),adndpcobas)
		if (allocated(MOene)) deallocate(MOene)
		allocate(MOene(numsaved))
		do iorb=1,numsaved
			MOene(iorb)=Emat(iorb,iorb)
		end do
		write(*,"(/,a)") " Energy of picked AdNDP orbitals:"
		do iorb=1,numsaved
			write(*,"(' Orbital:',i6,'  Energy (a.u./eV):',f12.6,f12.4)") iorb,MOene(iorb),MOene(iorb)*au2eV
		end do
		write(*,*)
		deallocate(adndpcobas,Emat,MOene)
	end if

end do

end subroutine


!!!------------- Define search list for exhaustive search
subroutine adndpdeflist(searchlist,lensearchlist)
use defvar
use util
implicit real*8 (a-h,o-z)
integer searchlisttmp(ncenter),searchlist(ncenter) !tmp verison is used to temporarily store index
integer lensearchlisttmp,lensearchlist !Effective length of the search list
integer tmparr(ncenter)
character cmd*200,elename*2
lensearchlisttmp=lensearchlist
searchlisttmp=searchlist
if (lensearchlisttmp>0) then
	write(*,"(' Currently',i5,' atoms are present in the search list:')") lensearchlisttmp
	do i=1,lensearchlisttmp
		write(*,"(i5,'(',a,')')",advance='no') searchlisttmp(i),a(searchlisttmp(i))%name
		if (mod(i,8)==0) write(*,*)
	end do
	write(*,*)
else
	write(*,*) "Current search list is empty"
end if
write(*,*)
write(*,*) "Exemplificative commands:"
write(*,*) "a 1,4,5,6 : Add atom 1,4,5,6 to the list"
write(*,*) "a 2-6     : Add atom 2,3,4,5,6 to the list"
write(*,*) "d 6,2,3   : Remove atom 6,2,3 from the list"
write(*,*) "d 2-6     : Remove atom 2,3,4,5,6 from the list"
write(*,*) "ae Al     : Add all aluminium atoms to the list"
write(*,*) "de H      : Remove all hydrogen atoms from the list"
write(*,*) "addall    : Add all atoms to the list"
write(*,*) "clean     : Clean the list"
write(*,*) "list      : Show current search list"
write(*,*) "help      : Show help information again"
write(*,*) "x         : Save the list and quit"
write(*,*) "q         : Quit without saving"
do while(.true.)
	read(*,"(a)") cmd
	
	if (cmd=="list") then
		if (lensearchlisttmp>0) then
			write(*,"('Currently',i5,' atoms are present in the search list:')") lensearchlisttmp
			do i=1,lensearchlisttmp
				write(*,"(i5,'(',a,')')",advance='no') searchlisttmp(i),a(searchlisttmp(i))%name
				if (mod(i,8)==0) write(*,*)
			end do
			write(*,*)
		else
			write(*,*) "Current search list is empty"
		end if
		write(*,*)
	else if (cmd=="help") then
		write(*,*)
		write(*,*) "Exemplificative commands:"
		write(*,*) "a 1,4,5,6 : Add atom 1,4,5,6 to the list"
		write(*,*) "a 2-6     : Add atom 2,3,4,5,6 to the list"
		write(*,*) "d 6,2,3   : Remove atom 6,2,3 from the list"
		write(*,*) "d 2-6     : Remove atom 2,3,4,5,6 from the list"
		write(*,*) "ae Al     : Add all aluminium atoms to the list"
		write(*,*) "de H      : Remove all hydrogen atoms from the list"
		write(*,*) "addall    : Add all atoms to the list"
		write(*,*) "clean     : Clean the list"
		write(*,*) "show      : Show current search list"
		write(*,*) "help      : Show help information again"
		write(*,*) "x         : Save the list and quit"
		write(*,*) "q         : Quit without saving"
	else if (cmd=='q') then
		write(*,*)
		exit
	else if (cmd=='x') then
		searchlist=searchlisttmp
		lensearchlist=lensearchlisttmp
		write(*,*) "Search list has been saved"
		if (lensearchlisttmp>0) then
			write(*,"('Currently',i5,' atoms are present in the search list:')") lensearchlisttmp
			do i=1,lensearchlisttmp
				write(*,"(i5,'(',a,')')",advance='no') searchlisttmp(i),a(searchlisttmp(i))%name
				if (mod(i,8)==0) write(*,*)
			end do
			write(*,*)
		else
			write(*,*) "Current search list is empty"
		end if
		write(*,*)
		exit
	else if (cmd=='addall') then
		lensearchlisttmp=ncenter
		forall (i=1:ncenter) searchlisttmp(i)=i
		write(*,*) "Done!"
	else if (cmd=='clean') then
		lensearchlisttmp=0
		write(*,*) "Done!"
	else if (cmd(1:2)=='ae'.or.cmd(1:2)=='de') then
			elename=cmd(4:5)
			call lc2uc(elename(1:1)) !Convert to upper case
			call uc2lc(elename(2:2)) !Convert to lower case
			icog=0
			do iele=1,nelesupp !Find corresponding atom index in periodic table
				if (elename==ind2name(iele)) then
					icog=1
					exit
				end if
			end do
			if (icog==1) then
				if (cmd(1:2)=='ae') then !add atom
					do icyclist=1,ncenter !Scan and find out corresponding atom from entire system
						if (a(icyclist)%index==iele) then
							if (any(searchlisttmp(1:lensearchlisttmp)==icyclist)) cycle !Check if it has presented in search list
							lensearchlisttmp=lensearchlisttmp+1
							searchlisttmp(lensearchlisttmp)=icyclist
						end if
					end do
				else !remove atom
					ipos=1
					do while(.true.)
						if (a(searchlisttmp(ipos))%index==iele) then
							if (lensearchlisttmp>=ipos+1) searchlisttmp(ipos:lensearchlisttmp-1)=searchlisttmp(ipos+1:lensearchlisttmp)
							lensearchlisttmp=lensearchlisttmp-1
						else
							ipos=ipos+1
						end if
						if (ipos>lensearchlisttmp) exit
					end do
				end if
				write(*,*) "Done!"
			else
				write(*,*) "Error: Unrecognizable element name"
			end if
	else if (cmd(1:2)=='a '.or.cmd(1:2)=='d ') then
		if (index(cmd,'-')==0) then !Doesn't use range select for atoms
			iterm=1
			do i=1,len_trim(cmd)
				if (cmd(i:i)==',') iterm=iterm+1
			end do
			read (cmd(3:len_trim(cmd)),*) tmparr(1:iterm)
		else
			do i=1,len_trim(cmd) !Find position of -
				if (cmd(i:i)=='-') exit
			end do
			read(cmd(3:i-1),*) ilow
			read(cmd(i+1:),*) ihigh
			iterm=ihigh-ilow+1
			forall (i=1:iterm) tmparr(i)=i+ilow-1
		end if
		
		if (cmd(1:2)=='a') then
			do i=1,iterm
				if (any(searchlisttmp(1:lensearchlisttmp)==tmparr(i))) cycle
				lensearchlisttmp=lensearchlisttmp+1
				searchlisttmp(lensearchlisttmp)=tmparr(i)
			end do
		else
			ipos=1
			do while(.true.)
				if (any( tmparr(1:iterm)==searchlisttmp(ipos) )) then
					if (lensearchlisttmp>=ipos+1) searchlisttmp(ipos:lensearchlisttmp-1)=searchlisttmp(ipos+1:lensearchlisttmp)
					lensearchlisttmp=lensearchlisttmp-1
				else
					ipos=ipos+1
				end if
				if (ipos>lensearchlisttmp) exit
			end do
		end if
		write(*,*) "Done!"
	else
		write(*,*) "Error: Unrecognizable input"
	end if
end do
end subroutine


!------- Load AONAO matrix and read "nbasis" from Gaussian output file
!Note: numNAO may be different with nbasis, when linear dependence occurs, NBO will delete some NAO, hence the numNAO<=nbasis
subroutine loadAONAO(AONAO,numNAO,ifound)
use defvar
use util
implicit real*8 (a-h,o-z)
real*8 AONAO(nbasis,numNAO)
character c80tmp*80
integer ifound
!Now load transformation matrix between NAOs and AOs
!Note that even for open-shell case, AONAO only be printed once, namely for density
open(10,file=filename,status="old")
call loclabel(10,"NAOs in the AO basis:",ifound,1)
read(10,"(a)") c80tmp
backspace(10)
nskipcol=16 !NBO3
if (c80tmp(2:2)==" ") nskipcol=17 !NBO6
if (ifound==0) then
	write(*,"(a)") " Error: Cannot found NAOs in the AO basis field in the Gaussian output file!"
	write(*,*)
	close(10)
	return
end if
write(*,"(a)") " Loading transformation matrix between original basis and NAO from Gaussian output file..." 
!Note: AONAO matrix in NBO output may be any number of columns (so that to ensure long data can be fully recorded), 
!so we must try to determine the actual number of rows and then use correct format to load it
!I assume that at least 5 columns and at most 8 columns
read(10,*)
read(10,*)
read(10,"(a)") c80tmp
if8col=index(c80tmp,'8')
if7col=index(c80tmp,'7')
if6col=index(c80tmp,'6')
if5col=index(c80tmp,'5')
backspace(10)
backspace(10)
backspace(10)
if (if8col/=0) then !8 columns
    call readmatgau(10,AONAO,0,"f8.4 ",nskipcol,8,3)
else if (if7col/=0) then !7 columns
	call readmatgau(10,AONAO,0,"f9.4 ",nskipcol,7,3)
else if (if6col/=0) then !6 columns
	call readmatgau(10,AONAO,0,"f10.4",nskipcol,6,3)
else if (if5col/=0) then !5 columns
	call readmatgau(10,AONAO,0,"f11.4",nskipcol,5,3)
end if
close(10)
end subroutine