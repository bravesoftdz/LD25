Unit game; {$INCLUDE defines.inc}


Interface

Procedure DamageMob(Const mID:uInt; Const Power:Double);
Procedure DamagePlayer(Const Power:Double);

Function PlayGame():Boolean;


Implementation
Uses
	SDL,
	ConfigFiles, FloatingText, Objects, Rooms, Shared, Sour;

Type
	TRoomChange = (
		RCHANGE_NONE,
		RCHANGE_UP,
		RCHANGE_RIGHT,
		RCHANGE_DOWN,
		RCHANGE_LEFT
	);

Const
	PAUSETXT_W = (64 - 35 - 2); 
	PAUSETXT_H = (32 - 7 - 2);

Var
	Frames, FrameTime, AniFra: uInt;
	FrameStr: ShortString;
	PauseTxt: Sour.TCrd;
	Paused, WantToQuit: Boolean;
	RoomChange: TRoomChange;
{$IFDEF DEVELOPER} 
	debugY,debugU,debugI:Boolean;
{$ENDIF}


Procedure GatherInput();
Begin
	While (SDL_PollEvent(@Ev)>0) do begin
		If (Ev.Type_ = SDL_QuitEv) then begin
			Shutdown:=True; WantToQuit:=True 
		end else
		If (Ev.Type_ = SDL_KeyDown) then begin
			If (Ev.Key.Keysym.Sym = SDLK_Escape) then WantToQuit:=True else
			If (Ev.Key.Keysym.Sym = KeyBind[Key_Up]        ) then Key[KEY_UP   ]     :=True else
			If (Ev.Key.Keysym.Sym = KeyBind[Key_RIGHT]     ) then Key[KEY_RIGHT]     :=True else
			If (Ev.Key.Keysym.Sym = KeyBind[Key_DOWN]      ) then Key[KEY_DOWN ]     :=True else
			If (Ev.Key.Keysym.Sym = KeyBind[Key_LEFT]      ) then Key[KEY_LEFT ]     :=True else
			If (Ev.Key.Keysym.Sym = KeyBind[Key_ShootLeft] ) then Key[KEY_ShootLeft] :=True else
			If (Ev.Key.Keysym.Sym = KeyBind[Key_ShootRight]) then Key[KEY_ShootRight]:=True else
			If (Ev.Key.Keysym.Sym = KeyBind[Key_VolDown]) then ChgVol(-1) else
			If (Ev.Key.Keysym.Sym = KeyBind[Key_VolUp])	then ChgVol(+1) else
			If (Ev.Key.Keysym.Sym = KeyBind[Key_Pause])	then Paused:=(Not Paused) else
			{$IFDEF DEVELOPER}
				If (Ev.Key.Keysym.Sym = SDLK_H) then begin 
					If (DeadTime <= 0) then Hero^.HP:=Hero^.MaxHP 
				end else
				If (Ev.Key.Keysym.Sym = SDLK_U) then debugU:=(Not debugU) else
				If (Ev.Key.Keysym.Sym = SDLK_I) then debugI:=(Not debugI) else
				If (Ev.Key.Keysym.Sym = SDLK_Y) then debugY:=(Not debugY) else
			{$ENDIF}
		end else
		If (Ev.Type_ = SDL_KeyUp) then begin
			If (Ev.Key.Keysym.Sym = KeyBind[Key_Up]        ) then Key[KEY_UP   ]     :=False else
			If (Ev.Key.Keysym.Sym = KeyBind[Key_RIGHT]     ) then Key[KEY_RIGHT]     :=False else
			If (Ev.Key.Keysym.Sym = KeyBind[Key_DOWN]      ) then Key[KEY_DOWN ]     :=False else
			If (Ev.Key.Keysym.Sym = KeyBind[Key_LEFT]      ) then Key[KEY_LEFT ]     :=False else
			If (Ev.Key.Keysym.Sym = KeyBind[Key_ShootLeft] ) then Key[KEY_ShootLeft] :=False else
			If (Ev.Key.Keysym.Sym = KeyBind[Key_ShootRight]) then Key[KEY_ShootRight]:=False else
		end else
		If (Ev.Type_ = SDL_VideoResize) then begin
			Shared.ResizeWindow(Ev.Resize.W,Ev.Resize.H,False);
			Paused:=True
		end else
		If (Ev.Type_ = SDL_ActiveEvent) then begin
			If (Ev.Active.State <> SDL_APPMOUSEFOCUS) and (Ev.Active.Gain = 0) then Paused:=True
		end
	end
End;

Procedure Animate(Const Ticks:uInt);
Begin
	{$IFNDEF DEVELOPER}
	AniFra:=(Ticks div AnimTime) mod 2;
	{$ELSE}
	If (Not debugY) 
		then AniFra:=(Ticks div AnimTime) mod 2
		else AniFra:=0;
	{$ENDIF}
End;

Procedure CalculateHero(Const Time:uInt);
Var
	C: sInt;
	XDif, YDif, ChkX, ChkY: Double;
Begin
	If (Hero^.HP > 0.0) then begin
		Hero^.Calculate(Time);
		
		XDif:=Hero^.XVel*Time/1000;
		YDif:=Hero^.YVel*Time/1000;
		
		// In developer mode, debugI allows for noclip.
		// Outside developer builds (or with disabled debugI), we need to check hero collisions.
		{$IFDEF DEVELOPER}
		If (Not debugI) then begin
		{$ENDIF}
			If (XDif<>0) then begin
				If (XDif<0) then ChkX:=Hero^.X else ChkX:=Hero^.X+Hero^.W-1;
				
				If (Not Room^.Collides(ChkX+XDif,Hero^.Y)) and (Not Room^.Collides(ChkX+XDif,Hero^.Y+Hero^.H-1)) then 
					Hero ^.X:=Hero^.X+XDif
			end;
			
			If (YDif<>0) then begin
				If (YDif<0) then ChkY:=Hero^.Y else ChkY:=Hero^.Y+Hero^.H-1;
				
				If (Not Room^.Collides(Hero^.X,ChkY+YDif)) and (Not Room^.Collides(Hero^.X+Hero^.W-1,ChkY+YDif)) then
					Hero^.Y:=Hero^.Y+YDif
			end;
		{$IFDEF DEVELOPER}
		end else begin 
			Hero^.X:=Hero^.X+XDif; Hero^.Y:=Hero^.Y+YDif 
		end {$ENDIF}
	
	end else begin
		If (DeadTime > 0) then 
			DeadTime-=Time
		else begin
			ChangeRoom(RespRoom[GameMode].X,RespRoom[GameMode].Y);
			Hero^.mX:=RespPos[GameMode].X; Hero^.mY:=RespPos[GameMode].Y;
			
			Hero^.HP:=Hero^.MaxHP;
			Hero^.FireTimer:=0;
			Hero^.InvTimer:=0;
			
			For C:=0 to 7 do
				If (ColState[C]=STATE_PICKED) then
					ColState[C]:=STATE_NONE;
			Carried:=0;
			
			Write('Saving game upon death... ');
			If (SaveGame(GameMode))
				then Writeln('Success!')
				else Writeln('Failed!')
		end 
	end
End;

Procedure CalculateCrystalPickup();
Var
	C: sInt;
Begin
	If (Not Crystal.IsSet) then Exit;
	If (Not Overlap(Hero^.X,Hero^.Y,Hero^.W,Hero^.H,Crystal.mX*TILE_W,Crystal.mY*TILE_H,TILE_W,TILE_H)) then Exit;
	
	If (Crystal.Col<>WOMAN) then begin
		ColState[Crystal.Col]:=STATE_PICKED; 
		Crystal.IsSet:=False;
		
		PlaySfx(SFX_EXTRA);
		Carried+=1
	end else If (Carried>0) then begin
		PlaySfx(SFX_EXTRA+1);
		Given+=Carried; Carried:=0;
		
		For C:=0 to 7 do begin
			If (ColState[C]=STATE_PICKED) then begin
				CentralPalette[C]:=PaletteColour[C];
				PaletteColour[C]:=GreyColour;
				ColState[C]:=STATE_GIVEN
			end;
			
			Hero^.MaxHP:=HERO_HEALTH*(1+(Given/14)); Hero^.HP:=Hero^.MaxHP;
			Hero^.FirePower:=HERO_FIREPOWER*(1+(Given/14));
			Hero^.InvLength:=Trunc(HERO_INVUL*(1+(Given/14)));
		end;
		
		// If this is the last crystal, switch the quit-flag so we exit to outro after this game cycle.
		If (Given >= 8) then
			WantToQuit:=True 
		else begin
			Write('Saving game upon progress... '); 
			If (SaveGame(GameMode)) 
				then Writeln('Success!')
				else Writeln('Failed!')
		end
	end;
End;

Procedure CalculateRoomChange();
Begin
	If (Hero^.iX < 0) then begin
		If (Room^.Tile[0][Hero^.mY]=TILE_ZONE) or (Room^.Tile[0][Hero^.mY]=TILE_ROOM) then
			RoomChange := RCHANGE_LEFT
	end else
	If (Hero^.iY < 0) then begin
		If (Room^.Tile[Hero^.mX][0]=TILE_ZONE) or (Room^.Tile[Hero^.mX][0]=TILE_ROOM) then
			RoomChange := RCHANGE_UP
	end else
	If (Hero^.iX > ((ROOM_W-1)*TILE_W)) then begin
		If (Room^.Tile[ROOM_W-1][Hero^.mY]=TILE_ZONE) or (Room^.Tile[ROOM_W-1][Hero^.mY]=TILE_ROOM) then
			RoomChange := RCHANGE_RIGHT
	end else
	If (Hero^.iY > ((ROOM_H-1)*TILE_H)) then begin
		If (Room^.Tile[Hero^.mX][ROOM_H-1]=TILE_ZONE) or (Room^.Tile[Hero^.mX][ROOM_H-1]=TILE_ROOM) then
			RoomChange := RCHANGE_DOWN
	end
End;

Procedure CalculateMonsters(Const Time:uInt);
Var
	M: sInt;
	E: PEntity;
	XDif, YDif, ChkX, ChkY: Double;
Begin
	If(Length(Mob)=0) then Exit;

	For M:=Low(Mob) to High(Mob) do begin
		If (Mob[M]=NIL) then Continue;
		
		E:=Mob[M];
		E^.Calculate(Time);
		
		XDif:=E^.XVel*Time/1000;
		YDif:=E^.YVel*Time/1000;
		If (XDif<>0) then begin
			If (XDif<0) then begin 
				E^.Face:=FACE_LEFT;  ChkX:=E^.X
			end else begin 
				E^.Face:=FACE_RIGHT; ChkX:=E^.X+E^.W-1 
			end;
			
			If (Not Room^.CollidesOrOutside(ChkX+XDif,E^.Y)) and (Not Room^.CollidesOrOutside(ChkX+XDif,E^.Y+E^.H-1)) then begin 
				E^.X:=E^.X+XDif; E^.XCol:=False 
			end else
				E^.XCol:=True;
		end else
			E^.XCol:=False;
		
		If (YDif<>0) then begin
			If (YDif<0) then ChkY:=E^.Y else ChkY:=E^.Y+E^.H-1;
			
			If (Not Room^.CollidesOrOutside(E^.X,ChkY+YDif)) and (Not Room^.CollidesOrOutside(E^.X+E^.W-1,ChkY+YDif)) then begin
				E^.Y:=E^.Y+YDif; E^.YCol:=False
			end else
				E^.YCol:=True
		end else 
			E^.YCol:=False;
		
		If (Hero^.HP > 0) and (Hero^.InvTimer <= 0) and (Overlap(Hero,E)) then begin 
			DamageMob(M,9.5); DamagePlayer(9.5) 
		end
	end
End;

Procedure CalculatePlayerBullets(Const Time:uInt);
Var
	B, M: sInt;
	XDif, YDif, ChkX, ChkY: Double;
Begin
	If (Length(PBul)=0) then Exit;
	
	For B:=Low(PBul) to High(PBul) do begin
		If (PBul[B]=NIL) then Continue;
		
		XDif:=PBul[B]^.XVel*Time/1000; YDif:=PBul[B]^.YVel*Time/1000;
		If (XDif<>0) then begin
			If (XDif<0) then ChkX:=PBul[B]^.X else ChkX:=PBul[B]^.X+PBul[B]^.W-1;
			
			If (Room^.CollidesOrOutside(ChkX+XDif,PBul[B]^.Y)) then begin
				Room^.HitSfx(ChkX+XDif,PBul[B]^.Y); PBul[B]^.HP:=-10 
			end else
			If (Room^.CollidesOrOutside(ChkX+XDif,PBul[B]^.Y+PBul[B]^.H-1)) then begin 
				Room^.HitSfx(ChkX+XDif,PBul[B]^.Y+PBul[B]^.H-1); PBul[B]^.HP:=-10
			end else
				PBul[B]^.X:=PBul[B]^.X+XDif
		end;
			
		If (YDif<>0) then begin
			If (YDif<0) then ChkY:=PBul[B]^.Y else ChkY:=PBul[B]^.Y+PBul[B]^.H-1;
			
			If (Room^.CollidesOrOutside(PBul[B]^.X,ChkY+YDif)) then begin 
				Room^.HitSfx(PBul[B]^.X,ChkY+YDif); PBul[B]^.HP:=-10 
			end else
			If (Room^.CollidesOrOutside(PBul[B]^.X+PBul[B]^.W-1,ChkY+YDif)) then begin 
				Room^.HitSfx(PBul[B]^.X+PBul[B]^.W-1,ChkY+YDif); PBul[B]^.HP:=-10
			end else
				PBul[B]^.Y:=PBul[B]^.Y+YDif
		end;
		
		If (PBul[B]^.HP <= 0) then begin
			Dispose(PBul[B],Destroy()); PBul[B]:=NIL; 
			Continue 
		end;
		
		If (Length(Mob)>0) then M:=Low(Mob) else M:=High(M);
		While (M<=High(Mob)) do begin
			If (Mob[M]=NIL) then begin 
				M+=1; Continue
			end;
			
			If (Overlap(PBul[B],Mob[M])) then begin
				DamageMob(M,PBul[B]^.Power);
				Dispose(PBul[B],Destroy()); PBul[B]:=NIL;
				M:=High(Mob)*2
			end else 
				M+=1
		end
	end
End;

Procedure CalculateEnemyBullets(Const Time:uInt);
Var
	B: sInt;
	XDif, YDif, ChkX, ChkY: Double;
Begin
	If (Length(EBul)=0) then Exit;
	
	For B:=Low(EBul) to High(EBul) do begin
		If (EBul[B]=NIL) then Continue;
		
		XDif:=EBul[B]^.XVel*Time/1000; 
		YDif:=EBul[B]^.YVel*Time/1000;
		
		If (XDif<>0) then begin
			If (XDif<0) then ChkX:=EBul[B]^.X else ChkX:=EBul[B]^.X+EBul[B]^.W-1;
			
			If (Room^.CollidesOrOutside(ChkX+XDif,EBul[B]^.Y)) then begin 
				Room^.HitSfx(ChkX+XDif,EBul[B]^.Y); EBul[B]^.HP:=-10 
			end else
			If (Room^.CollidesOrOutside(ChkX+XDif,EBul[B]^.Y+EBul[B]^.H-1)) then begin
				Room^.HitSfx(ChkX+XDif,EBul[B]^.Y+EBul[B]^.H-1); EBul[B]^.HP:=-10 
			end else
				EBul[B]^.X:=EBul[B]^.X+XDif
		end;
		
		If (YDif<>0) then begin
			If (YDif<0) then ChkY:=EBul[B]^.Y else ChkY:=EBul[B]^.Y+EBul[B]^.H-1;
			
			If (Room^.CollidesOrOutside(EBul[B]^.X,ChkY+YDif)) then begin 
				Room^.HitSfx(EBul[B]^.X,ChkY+YDif); EBul[B]^.HP:=-10 
			end else
			If (Room^.CollidesOrOutside(EBul[B]^.X+EBul[B]^.W-1,ChkY+YDif)) then begin 
				Room^.HitSfx(EBul[B]^.X+EBul[B]^.W-1,ChkY+YDif); EBul[B]^.HP:=-10
			end else
				EBul[B]^.Y:=EBul[B]^.Y+YDif
		end;
		
		If (EBul[B]^.HP <= 0) then begin
			Dispose(EBul[B],Destroy()); EBul[B]:=NIL;
			Continue 
		end;
		
		If (Hero^.HP > 0) and (Hero^.InvTimer <= 0) and (Overlap(EBul[B],Hero)) then begin 
			DamagePlayer(EBul[B]^.Power);
			Dispose(EBul[B],Destroy()); EBul[B]:=NIL
		end;
	end;
End;

Procedure CalculateGibs(Const Time:uInt);
Var
	G: sInt;
	XDif, YDif, ChkX, ChkY: Double;
Begin
	If (Length(Gib)=0) then Exit;
	
	For G:=Low(Gib) to High(Gib) do begin
		If (Gib[G]=NIL) then Continue;
		
		XDif:=Gib[G]^.XVel*Time/1000; 
		YDif:=Gib[G]^.YVel*Time/1000;
		
		If (XDif<>0) then begin
			If (XDif<0) then ChkX:=Gib[G]^.X else ChkX:=Gib[G]^.X+Gib[G]^.W-1;
			
			If (Room^.CollidesOrOutside(ChkX+XDif,Gib[G]^.Y)) or (Room^.CollidesOrOutside(ChkX+XDif,Gib[G]^.Y+Gib[G]^.H-1))
				then Gib[G]^.HP:=-10 
				else Gib[G]^.X:=Gib[G]^.X+XDif
		end;
		
		If (YDif<>0) then begin
			If (YDif<0) then ChkY:=Gib[G]^.Y else ChkY:=Gib[G]^.Y+Gib[G]^.H-1;
			
			If (Room^.CollidesOrOutside(Gib[G]^.X,ChkY+YDif)) or (Room^.CollidesOrOutside(Gib[G]^.X+Gib[G]^.W-1,ChkY+YDif))
				then Gib[G]^.HP:=-10 
				else Gib[G]^.Y:=Gib[G]^.Y+YDif
		end;
		
		If (Gib[G]^.HP <= 0) then begin
			Dispose(Gib[G],Destroy()); Gib[G]:=NIL 
		end
	end;
End;

Procedure CalculateGameCycle(Const Time:uInt);
Begin
	CalculateHero(Time);
	CalculateCrystalPickup();
	CalculateRoomChange();
	
	CalculatePlayerBullets(Time);
	{$IFDEF DEVELOPER} If (Not debugY) then {$ENDIF} CalculateMonsters(Time);
	CalculateEnemyBullets(Time);
	CalculateGibs(Time);
End;

Procedure DrawRoom();
Var
	X, Y: sInt;
	Src, Dst: Sour.TRect;
Begin
	// All tiles have the same size, no need to set this in the loop 
	Src.W:=TILE_W; Src.H:=TILE_H; 
	Dst.W:=TILE_W; Dst.H:=TILE_H;
	
	Src.X:=AniFra*TILE_W;
	For Y:=0 to (ROOM_H-1) do For X:=0 to (ROOM_W-1) do begin
		If (Room^.Tile[X][Y]=TILE_NONE) then Continue;
		Dst.X:=X*TILE_W; Dst.Y:=Y*TILE_H;
		Src.Y:=Room^.Tile[X][Y]*TILE_H;
		Sour.DrawImage(TileGfx,@Src,@Dst,Room^.TCol[X][Y])
	end
End;

Procedure DrawGibs();
Var
	G: sInt;
	Rect: Sour.TRect;
Begin
	For G:=Low(Gib) to High(Gib) do
		If (Gib[G]<>NIL) then begin
			Sour.SetRect(Rect,Gib[G]^.iX,Gib[G]^.iY,Gib[G]^.Rect.W,Gib[G]^.Rect.H);
			Sour.DrawImage(Gib[G]^.Gfx,@Gib[G]^.Rect,@Rect,Gib[G]^.Col)
		end
End;

Procedure DrawMonsters();
Var
	M: sInt;
	E: PEntity;
	Crd: Sour.TCrd;
	Rect: Sour.TRect;
Begin
	For M:=Low(Mob) to High(Mob) do
		If (Mob[M]<>NIL) then begin
			E:=Mob[M]; Crd:=E^.GetCrd;
			Rect:=Sour.MakeRect(AniFra*E^.W,E^.Face*E^.H,E^.W,E^.H);
			Sour.DrawImage(E^.Gfx,@Rect,@Crd,E^.Col)
		end
End;

Procedure DrawPlayerBullets();
Var
	B: sInt;
	E: PEntity;
	Crd: Sour.TCrd;
	Rect: Sour.TRect;
Begin
	For B:=Low(PBul) to High(PBul) do
		If (PBul[B]<>NIL) then begin
			E:=PBul[B]; Crd:=E^.GetCrd;
			Rect:=Sour.MakeRect(AniFra*E^.W,E^.Face*E^.H,E^.W,E^.H);
			Sour.DrawImage(E^.Gfx,@Rect,@Crd,E^.Col)
		end
End;

Procedure DrawEnemyBullets();
Var
	B: sInt;
	E: PEntity;
	Crd: Sour.TCrd;
	Rect: Sour.TRect;
Begin
	For B:=Low(EBul) to High(EBul) do
		If (EBul[B]<>NIL) then begin
			E:=EBul[B]; Crd:=E^.GetCrd;
			Rect:=Sour.MakeRect(AniFra*E^.W,E^.Face*E^.H,E^.W,E^.H);
			Sour.DrawImage(E^.Gfx,@Rect,@Crd,E^.Col)
		end
End;

Procedure DrawHero();
Var
	Crd: Sour.TCrd;
	Rect: Sour.TRect;
	C, X: sInt;
	Col: Sour.TColour;
Begin
	If (Hero^.HP <= 0.0) then Exit;
	
	// Set target drawing coord and source rect
	Sour.SetCrd(Crd, Hero^.iX, Hero^.iY);
	Sour.SetRect(Rect, AniFra*Hero^.W, Hero^.Face*Hero^.H, Hero^.W, Hero^.H);
	
	// If hero has taken damage recently, randomly move target position to make a "damage shake" effect
	If (Hero^.InvTimer > 0) then begin
		Crd.X+=Random(-1,1); Crd.Y+=Random(-1,1) 
	end;
	
	// If hero is carrying a colour, randomly colourise the bastard
	If (Carried>0) then begin
		If (Random(5)<>0) then 
			Col:=GreyColour 
		else begin
			C:=Random(Carried)+1; X:=-1;
			Repeat 
				X+=1;
				If (ColState[X]=STATE_PICKED) then C-=1
			Until (C = 0);
			Col:=PaletteColour[X]
		end
	end else
		Col:=GreyColour;
	
	Sour.DrawImage(Hero^.Gfx, @Rect, @Crd, @Col)
End;

Procedure DrawCrystal();
Var
	Crd: Sour.TCrd;
	Src: Sour.TRect;
Begin
	If(Not Crystal.IsSet) then Exit;
	
	Sour.SetRect(Src,AniFra*TILE_W,Crystal.Col*TILE_H,TILE_W,TILE_H);
	Sour.SetCrd(Crd,Crystal.mX*TILE_W,Crystal.mY*TILE_H);
	
	If (Crystal.Col <> WOMAN)
		then Sour.DrawImage(ColGfx,@Src,@Crd)
		else Sour.DrawImage(ColGfx,@Src,@Crd,@CentralPalette[FrameTime div (1000 div 8)])
End;

Procedure DrawFloatingTexts();
Var
	ft: sInt;
Begin
	For ft:=Low(FloatTxt) to High(FloatTxt) do
		If (FloatTxt[ft]<>NIL) then
			Sour.PrintText(FloatTxt[ft]^.Text,Font,FloatTxt[ft]^.X,FloatTxt[ft]^.Y,FloatTxt[ft]^.Col)
End;

Procedure DrawUI();
Const
	HPrect: Sour.TRect = (X: 0; Y:0; W:16; H:16);
	ColRect: Sour.TRect = (X: 16; Y:0; W:16; H:16);
	FPSRect: Sour.TRect = (X: 32; Y:0; W:16; H:16);
	VolRect: Sour.TRect = (X: 48; Y:0; W:16; H:16);
Var
	Crd: Sour.TCrd;
	Rect, PauseRect: Sour.TRect;
	C: sInt;
Begin
	// Health indicator
	Crd:=Sour.MakeCrd(0,0);
	Sour.DrawImage(UIgfx,@HPrect,@Crd);
	If (Hero^.HP > 0) then begin
		Sour.SetRect(Rect,3,9,1+Trunc(9*Hero^.HP/Hero^.MaxHP),4);
		If (Hero^.InvTimer <= 0)
			then Sour.FillRect(@Rect,@WhiteColour)
			else Sour.FillRect(@Rect,@GreyColour)
	end;

	// Colour indicator
	Crd:=Sour.MakeCrd(RESOL_W-16,0);
	Sour.DrawImage(UIgfx,@ColRect,@Crd);
	For C:=0 to 7 do begin
		If (ColState[C]=STATE_NONE) then Continue;
		
		Rect.X:=RESOL_W-14+((C mod 4)*3); 
		If ((C mod 4)>1) then Rect.X+=1;
		
		Rect.Y:=09; 
		If (C>=4) then Rect.Y+=3;
		
		// For given colours, draw a 2x2 rectangle.
		// For carried colours, draw two (randomly selected) pixels in the 2x2 rectangle area.
		If (ColState[C]=STATE_GIVEN) then begin
			Rect.W:=2; Rect.H:=2;
			Sour.FillRect(@Rect,UIcolour[C])
		end else begin
			Rect.W:=1; Rect.H:=1;
			Crd.X:=Rect.X; Crd.Y:=Rect.Y;
			Rect.X+=Random(2); Rect.Y+=Random(2);
			Sour.FillRect(@Rect,UIcolour[C]);
			Rect.X:=Crd.X+1-Random(2); Rect.Y:=Crd.Y+1-Random(2);
			Sour.FillRect(@Rect,UIcolour[C])
		end
	end;

	// Volume indicator
	Crd:=Sour.MakeCrd(0,RESOL_H-16);
	Sour.DrawImage(UIgfx,@VolRect,@Crd);
	For C:=GetVol() downto 1 do begin
		Rect.X:=(C*2); Rect.Y:=RESOL_H-2-C;
		Rect.W:=2; Rect.H:=C;
		Sour.FillRect(@Rect,@WhiteColour)
	end;

	// Frames per second indicator
	Crd:=Sour.MakeCrd(RESOL_W-16,RESOL_H-16);
	Sour.DrawImage(UIgfx,@FPSrect,@Crd);
	Sour.PrintText(FrameStr,NumFont,(RESOL_W-8),(RESOL_H-7),ALIGN_CENTER);

	// If paused, draw frame with "PAUSED" bouncing
	If (Paused) then begin
		PauseRect.X := ((RESOL_W - 64) div 2); 
		PauseRect.Y := ((RESOL_H - 32) div 2); 
		PauseRect.W := 64; 
		PauseRect.H := 32;
		
		Sour.FillRect(@PauseRect,@WhiteColour);
		
		With PauseRect do begin X+=1; Y+=1; W-=2; H-=2 end;
		Sour.FillRect(@PauseRect,@BlackColour);
		
		Sour.PrintText('PAUSED',Font,PauseRect.X+PauseTxt.X,PauseRect.Y+PauseTxt.Y);
	end
End;

Procedure DrawFrame();
begin
	Sour.BeginFrame();

	DrawRoom();

	If (Length(Gib)>0) then DrawGibs();
	If (Length(Mob)>0) then DrawMonsters();
	If (Length(PBul)>0) then DrawPlayerBullets();
	If (Length(EBul)>0) then DrawEnemyBullets();

	DrawHero();
	DrawCrystal();
	
	If (Length(FloatTxt)>0) then DrawFloatingTexts();

	{$IFDEF DEVELOPER} If Not (debugU) then {$ENDIF} DrawUI();

	// Swap OGL buffers, sending the current frame to video display.
	Sour.FinishFrame()
end;

Procedure CountFrames(Const Time:uInt);
Begin
	Frames+=1; FrameTime+=Time;
	
	If (FrameTime >= 1000) then begin
		If (Paused) then begin 
			PauseTxt.X:=Random(PAUSETXT_W); PauseTxt.Y:=Random(PAUSETXT_H) 
		end;
		
		WriteStr(FrameStr,Frames);
		FrameTime-=1000; Frames:=0
	end;
	// Count frames, duh
End;

Procedure PerformRoomChange();
Begin
	Case (RoomChange) of
		RCHANGE_UP: begin
			If (ChangeRoom(Room^.X,Room^.Y-1)) then Hero^.mY:=(ROOM_H-1)
		end;
		
		RCHANGE_RIGHT: begin
			If (ChangeRoom(Room^.X+1,Room^.Y)) then Hero^.mX:=0
		end;
		
		RCHANGE_DOWN: begin
			If (ChangeRoom(Room^.X,Room^.Y+1)) then Hero^.mY:=0
		end;
		
		RCHANGE_LEFT: begin
			If (ChangeRoom(Room^.X-1,Room^.Y)) then Hero^.mX:=(ROOM_W-1)
		end
	end;
	
	RoomChange := RCHANGE_NONE
End;


Procedure DamageMob(Const mID:uInt; Const Power:Double);
Begin
	Mob[mID]^.HP-=Power;
	If (Mob[mID]^.HP <= 0) then begin
		If (Mob[mID]^.SwitchNum >= 0) then Switch[Mob[mID]^.SwitchNum]:=True;

		PlaceGibs(Mob[mID]); 
		PlaySfx(Mob[mID]^.SfxID);
		
		Dispose(Mob[mID],Destroy()); Mob[mID]:=NIL
	end 
End;

Procedure DamagePlayer(Const Power:Double);
Begin
	Hero^.HP-=Power;
	Hero^.InvTimer := Hero^.InvLength;
	
	If (Hero^.HP <= 0) then begin
		DeadTime:=DeathLength;
		PlaceGibs(Hero);
		
		PlaySfx(SFX_EXTRA+2)
	end else
		PlaySfx(SFX_HIT)
End;

Function PlayGame():Boolean;
Var
	Time, Ticks: uInt;
Begin
	GetDeltaTime(Time);
	SDL_ShowCursor(0);
	
	RoomChange:=RCHANGE_NONE;
	Paused:=False; WantToQuit:=False; 
	Frames:=0; FrameTime:=0; FrameStr:='???';
	
	PauseTxt.X:=PAUSETXT_W div 2; PauseTxt.Y:=PAUSETXT_H div 2;
	Sour.SetFontScaling(Font,1); 
	
	{$IFDEF DEVELOPER} debugY:=False; debugU:=False; debugI:=False; {$ENDIF}
	Repeat
		If (RoomChange <> RCHANGE_NONE) then PerformRoomChange();
		
		GetDeltaTime(Time, Ticks);
		Animate(Ticks);
		GatherInput();

		If (Not Paused) then CalculateGameCycle(Time);

		DrawFrame();
		CountFrames(Time);

	Until WantToQuit;
	
	SDL_ShowCursor(1);
	Exit(Given >= 8)
End;

End.
