import Foundation

internal enum YouTubeEmbed {
    static func origin(bundleId: String) -> String {
        return "https://\(bundleId.lowercased())"
    }

    static func page(video: YouTubeVideo, origin: String, startSeconds: Double, autoplay: Bool) -> String {
        let start = startSeconds.isFinite ? max(0.0, min(startSeconds, 604800.0)) : 0.0
        let autoplayFlag = autoplay ? "true" : "false"

        return """
        <!doctype html>
        <html><head>
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <meta name="referrer" content="strict-origin-when-cross-origin">
          <style>
            html,body{margin:0;width:100%;height:100%;background:#000;overflow:hidden}
            #player{width:100%;height:100%;border:0}
          </style>
        </head><body><div id="player"></div>
          <script>
            (function(){
              var player, ready=false, error=null, pendingSeek=null, seekAt=0, suspended=document.hidden;
              var state={ready:false,playerState:-1,currentSeconds:\(start),durationSeconds:0,error:null};
              function snapshot(){
                if(ready){
                  try{
                    state.playerState=player.getPlayerState();
                    state.currentSeconds=player.getCurrentTime()||0;
                    state.durationSeconds=player.getDuration()||0;
                    if(pendingSeek!==null && (Math.abs(state.currentSeconds-pendingSeek)<1 || Date.now()-seekAt>1800)) pendingSeek=null;
                  }catch(e){}
                }
                state.ready=ready; state.error=error; return state;
              }
              window.formPlayer={
                snapshot:snapshot,
                fail:function(code){error=String(code);},
                play:function(){if(ready&&!suspended){if(player.getPlayerState()===0)player.seekTo(0,true);player.playVideo();}},
                pause:function(){if(ready)player.pauseVideo();},
                setVisible:function(visible){suspended=!visible;if(suspended&&ready)player.pauseVideo();},
                seek:function(offset){
                  if(!ready)return;
                  var s=snapshot(), base=pendingSeek===null?s.currentSeconds:pendingSeek;
                  var target=Math.max(0,base+offset);
                  if(s.durationSeconds>0)target=Math.min(s.durationSeconds,target);
                  pendingSeek=target;seekAt=Date.now();
                  var resume=s.playerState===1||s.playerState===3;
                  player.seekTo(target,true);
                  if(!resume)player.pauseVideo();
                }
              };
              window.onYouTubeIframeAPIReady=function(){
                player=new YT.Player('player',{
                  width:'100%',height:'100%',videoId:'\(video.id)',
                  playerVars:{controls:0,fs:0,playsinline:1,rel:0,autoplay:0,origin:'\(origin)',start:Math.floor(\(start))},
                  events:{
                    onReady:function(){ready=true;if(\(autoplayFlag)&&!suspended&&!document.hidden)player.playVideo();},
                    onStateChange:function(e){state.playerState=e.data;if(suspended&&(e.data===1||e.data===3))player.pauseVideo();},
                    onError:function(e){error=String(e.data);},
                    onAutoplayBlocked:function(){state.playerState=2;}
                  }
                });
              };
              document.addEventListener('visibilitychange',function(){window.formPlayer.setVisible(!document.hidden);});
              window.addEventListener('pagehide',function(){window.formPlayer.setVisible(false);});
            })();
          </script>
          <script src="https://www.youtube.com/iframe_api" onerror="window.formPlayer.fail('network')"></script>
        </body></html>
        """
    }
}
